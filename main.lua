-- Mandelbrot set explorer — hybrid renderer.
-- Below a zoom threshold the entire fractal is computed per-pixel in the
-- fragment shader (shader.glsl, plain fp32) — fast on every platform.
-- Beyond that, fp32 precision in GPU shaders degrades into blocky artifacts
-- (GLSL compilers here fold compensated "double-single" arithmetic away, and
-- this GLSL level has no fma/bit ops to prevent it), so deep zooms render on
-- the CPU:  the native C library via LuaJIT FFI when available, otherwise a
-- pure-Lua fallback (web builds via love.js).

local width, height = 800, 600
local max_iter = 100

-- View parameters
local centerX, centerY = -0.5, 0.0
local zoom = 1.0
local baseHalfWidth = 2.5
local baseHalfHeight = 2.0

-- GPU (plain fp32) rendering stays crisp until blocky fp32 quantization
-- (~1e-7 absolute) reaches a meaningful fraction of a pixel:
-- pixel size = span/width = 5/(zoom*width). 1e4 keeps the error well below it.
local GLSL_ZOOM_LIMIT = 1e4
local gpuMode = true

-- Control speeds
local panSpeed = 1.0

-- Native C library via LuaJIT FFI (desktop builds only, used for deep zoom).
-- Web builds via love.js don't have LuaJIT/FFI, so fall back to pure Lua.
local ffi, libname
local usingNative = false
local mandelbrotLib

if type(rawget(_G, "jit")) == "table" and pcall(require, "ffi") then
    local ok = pcall(function()
        ffi = require("ffi")
        ffi.cdef[[
            void generate_mandelbrot(uint8_t* pixels, int width, int height,
                                     double centerX, double centerY, double zoom,
                                     int max_iter, int threads, int aaEnabled);
            int get_thread_count();
        ]]

        if jit.os == "Windows" then
            libname = "mandelbrot.dll"
        elseif jit.os == "OSX" then
            libname = "mandelbrot.dylib"
        else
            libname = "mandelbrot.so"
        end

        local path = love.filesystem.getSource() .. "/" .. libname
        mandelbrotLib = ffi.load(path)
    end)
    usingNative = ok
end

-- Pure-Lua deep-zoom fallback renderer (web builds via love.js, where there
-- is no LuaJIT FFI). Produces the same output as the C library, single-threaded.
local COLOR_TABLE_SIZE = 1024
local color_table = {}
local color_table_max_iter = -1

local function init_color_table(max_iter)
    for i = 1, COLOR_TABLE_SIZE do
        local t = (i - 1) / (COLOR_TABLE_SIZE - 1)
        local oneMinusT = 1 - t
        color_table[i] = {
            r = math.floor(9 * oneMinusT * t * t * t * 255 + 0.5),
            g = math.floor(15 * oneMinusT * oneMinusT * t * t * 255 + 0.5),
            b = math.floor(8.5 * oneMinusT * oneMinusT * oneMinusT * t * 255 + 0.5),
        }
    end
    color_table_max_iter = max_iter
end

-- Pure-Lua fallback for the deep-zoom CPU path (web builds).
local previewScale = usingNative and 3 or 5
local previewWidth, previewHeight
local previewScaleX, previewScaleY
local previewImageData, previewImage
local previewEnabled = true
local aaEnabled = false
local isPreviewActive = false
local lastInteractionTime = 0
local idleRenderDelay = usingNative and 0.1 or 0.5
local needFullRender = false

-- UI state
local statsExpanded = true
local statsButtonX, statsButtonY = 10, 10
local statsButtonWidth, statsButtonHeight = 20, 20
local previewToggleX, previewToggleY = 10, 0
local previewToggleW, previewToggleH = 190, 30
local aaToggleX, aaToggleY = 10, 0
local aaToggleW, aaToggleH = 190, 30
local aboutOpen = false
local aboutButtonWidth, aboutButtonHeight = 64, 20
local aboutButtonX, aboutButtonY = 0, 0

local shader
local threadCount

local imageData, mandelbrotImage

function love.load()
    pcall(function()
        love.window.setMode(0, 0, { fullscreen = true })
    end)
    width, height = love.graphics.getDimensions()

    threadCount = usingNative and mandelbrotLib.get_thread_count() or 1

    shader = love.graphics.newShader("shader.glsl")

    imageData = love.image.newImageData(width, height)
    mandelbrotImage = love.graphics.newImage(imageData)

    previewWidth = math.max(1, math.floor(width / previewScale))
    previewHeight = math.max(1, math.floor(height / previewScale))
    previewScaleX = width / previewWidth
    previewScaleY = height / previewHeight
    previewImageData = love.image.newImageData(previewWidth, previewHeight)
    previewImage = love.graphics.newImage(previewImageData)
    previewImage:setFilter("linear", "linear")

    generateFrame(false)
end

function love.resize(w, h)
    width, height = w, h
end

local function computeIterations()
    local safeZoom = math.max(zoom, 1e-10)
    local calculated = 100 + math.floor(math.log(safeZoom) * 50)
    local limit = zoom > 1 and 2000 or 300
    return math.max(50, math.min(calculated, limit))
end

-- CPU renderer: fills targetData (C via FFI, or the pure-Lua fallback).
local function generateFrameLua(targetData, targetWidth, targetHeight)
    if color_table_max_iter ~= max_iter then
        init_color_table(max_iter)
    end

    local scale = 1.0 / zoom
    local xmin = centerX - baseHalfWidth * scale
    local xmax = centerX + baseHalfWidth * scale
    local ymin = centerY - baseHalfHeight * scale
    local ymax = centerY + baseHalfHeight * scale
    local dx = (xmax - xmin) / targetWidth
    local dy = (ymax - ymin) / targetHeight

    local sampleOffset = 0.25
    local lastColorIndex = COLOR_TABLE_SIZE
    local maxIter = max_iter
    local invMaxIter = 1.0 / max_iter
    local cr, ci, iter, zr, zi, zr2, zi2, colorIndex

    for y = 0, targetHeight - 1 do
        local ciBase = ymin + y * dy
        local ci1 = ymin + (y + (0 + sampleOffset) * 0.5) * dy
        local ci2 = ymin + (y + (1 + sampleOffset) * 0.5) * dy
        for x = 0, targetWidth - 1 do
            local accumR, accumG, accumB, sampleCount = 0, 0, 0, 1

            if aaEnabled then
                sampleCount = 4
                local cr1 = xmin + (x + (0 + sampleOffset) * 0.5) * dx
                local cr2 = xmin + (x + (1 + sampleOffset) * 0.5) * dx
                for sy = 0, 1 do
                    ci = sy == 0 and ci1 or ci2
                    for sx = 0, 1 do
                        cr = sx == 0 and cr1 or cr2
                        zr, zi, zr2, zi2, iter = 0, 0, 0, 0, 0
                        while zr2 + zi2 < 4.0 and iter < maxIter do
                            zi = 2.0 * zr * zi + ci
                            zr = zr2 - zi2 + cr
                            zr2 = zr * zr
                            zi2 = zi * zi
                            iter = iter + 1
                        end
                        colorIndex = math.min(math.floor(iter * invMaxIter * (lastColorIndex - 1)) + 1, lastColorIndex)
                        local color = color_table[colorIndex]
                        accumR = accumR + color.r
                        accumG = accumG + color.g
                        accumB = accumB + color.b
                    end
                end
            else
                cr = xmin + x * dx
                zr, zi, zr2, zi2, iter = 0, 0, 0, 0, 0
                while zr2 + zi2 < 4.0 and iter < maxIter do
                    zi = 2.0 * zr * zi + ciBase
                    zr = zr2 - zi2 + cr
                    zr2 = zr * zr
                    zi2 = zi * zi
                    iter = iter + 1
                end
                colorIndex = math.min(math.floor(iter * invMaxIter * (lastColorIndex - 1)) + 1, lastColorIndex)
                local color = color_table[colorIndex]
                accumR, accumG, accumB = color.r, color.g, color.b
            end

            targetData:setPixel(x, y,
                accumR * 0.00392156862745098 / sampleCount,
                accumG * 0.00392156862745098 / sampleCount,
                accumB * 0.00392156862745098 / sampleCount,
                1)
        end
    end
end

function generateFrame(usePreview)
    local targetWidth = usePreview and previewWidth or width
    local targetHeight = usePreview and previewHeight or height

    if usingNative then
        local pixelCount = targetWidth * targetHeight * 4
        local buffer = ffi.new("uint8_t[?]", pixelCount)
        local renderIter = max_iter

        mandelbrotLib.generate_mandelbrot(buffer, targetWidth, targetHeight, centerX, centerY, zoom, renderIter, threadCount, aaEnabled and 1 or 0)

        local targetData = usePreview and previewImageData or imageData
        local pixelPtr = targetData:getFFIPointer()
        ffi.copy(pixelPtr, buffer, pixelCount)
    else
        local targetData = usePreview and previewImageData or imageData
        generateFrameLua(targetData, targetWidth, targetHeight)
    end

    if usePreview then
        previewImage:replacePixels(previewImageData)
        isPreviewActive = true
        needFullRender = true
    else
        mandelbrotImage:replacePixels(imageData)
        isPreviewActive = false
        needFullRender = false
    end
end

function love.update(dt)
    local moveAmount = panSpeed * (baseHalfWidth / zoom) * dt
    local zoomSpeed = 1.05  -- Zoom 5% per zoom action

    local wasGpuMode = gpuMode
    local isZoomingOrPanning = false

    if love.keyboard.isDown('w') then
        centerY = centerY - moveAmount
        isZoomingOrPanning = true
    end
    if love.keyboard.isDown('s') then
        centerY = centerY + moveAmount
        isZoomingOrPanning = true
    end
    if love.keyboard.isDown('a') then
        centerX = centerX - moveAmount
        isZoomingOrPanning = true
    end
    if love.keyboard.isDown('d') then
        centerX = centerX + moveAmount
        isZoomingOrPanning = true
    end

    if love.keyboard.isDown('z') then
        zoom = zoom * zoomSpeed
        isZoomingOrPanning = true
    end
    if love.keyboard.isDown('x') then
        zoom = zoom / zoomSpeed
        zoom = math.max(zoom, 1e-10)
        isZoomingOrPanning = true
    end

    gpuMode = zoom < GLSL_ZOOM_LIMIT

    local modeChanged = gpuMode ~= wasGpuMode

    if gpuMode then
        -- GPU path renders live; nothing else to do. Cancel pending CPU work.
        needFullRender = false
        isPreviewActive = false
        max_iter = computeIterations()
    else
        -- Deep zoom: CPU rendering with interaction preview.
        if modeChanged then
            -- Switching to the slow CPU path: preview back on by default.
            previewEnabled = true
        end
        max_iter = computeIterations()
        if isZoomingOrPanning then
            lastInteractionTime = love.timer.getTime()
            if previewEnabled then
                generateFrame(true)
            else
                generateFrame(false)
            end
        elseif modeChanged or (previewEnabled and needFullRender
                and love.timer.getTime() - lastInteractionTime > idleRenderDelay) then
            generateFrame(false)
        end
    end
end

function love.draw()
    local renderer = gpuMode and "GPU (GLSL)"
        or (usingNative and "CPU fp64 (native C)" or "CPU fp64 (Lua fallback)")

    if gpuMode then
        -- GPU pass: one fullscreen quad, fractal computed per-pixel in the shader.
        love.graphics.setShader(shader)
        shader:send("center", { centerX, centerY })
        shader:send("span", { (baseHalfWidth * 2) / zoom, (baseHalfHeight * 2) / zoom })
        shader:send("screenSize", { width, height })
        shader:send("maxiter", max_iter)
        shader:send("aa", aaEnabled and 1.0 or 0.0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, width, height)
        love.graphics.setShader()
    else
        -- CPU pass: the rendered image (full-res or interaction preview).
        if isPreviewActive then
            love.graphics.draw(previewImage, 0, 0, 0, previewScaleX, previewScaleY)
        else
            love.graphics.draw(mandelbrotImage, 0, 0)
        end
    end

    -- Stats panel
    love.graphics.setColor(0.2, 0.2, 0.2, 0.7)
    love.graphics.rectangle("fill", statsButtonX, statsButtonY, statsButtonWidth, statsButtonHeight)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", statsButtonX, statsButtonY, statsButtonWidth, statsButtonHeight)

    love.graphics.setColor(1, 1, 1, 0.8)
    if statsExpanded then
        love.graphics.polygon("fill",
            statsButtonX + 10, statsButtonY + 5,
            statsButtonX + 5, statsButtonY + 15,
            statsButtonX + 15, statsButtonY + 15
        )
    else
        love.graphics.polygon("fill",
            statsButtonX + 5, statsButtonY + 5,
            statsButtonX + 5, statsButtonY + 15,
            statsButtonX + 15, statsButtonY + 10
        )
    end

    if statsExpanded then
        local statsX = statsButtonX + statsButtonWidth + 10
        local rows = (usingNative and not gpuMode) and 6 or 5
        love.graphics.setColor(0.08, 0.08, 0.08, 0.75)
        love.graphics.rectangle("fill", statsX - 10, 4, 220, rows * 20 + 8, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        local zoomPower = math.log10(math.max(zoom, 1e-10))
        love.graphics.print("Center: (" .. string.format("%.5f", centerX) ..
                            ", " .. string.format("%.5f", centerY) .. ")", statsX, 10)
        love.graphics.print("Zoom: 10^" .. string.format("%.2f", zoomPower), statsX, 30)
        love.graphics.print("Max Iterations: " .. max_iter, statsX, 50)
        love.graphics.print("Renderer: " .. renderer, statsX, 70)
        if usingNative and not gpuMode then
            love.graphics.print("Threads: " .. tostring(threadCount), statsX, 90)
            love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), statsX, 110)
        else
            love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), statsX, 90)
        end
    end

    aaToggleY = height - aaToggleH - 10
    previewToggleY = aaToggleY - previewToggleH - 10

    -- Antialias toggle
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", aaToggleX, aaToggleY, aaToggleW, aaToggleH, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", aaToggleX, aaToggleY, aaToggleW, aaToggleH, 6, 6)
    love.graphics.print("Antialias: " .. (aaEnabled and "ON" or "OFF"), aaToggleX + 10, aaToggleY + 10)

    -- Preview toggle (promotes fast low-res renders on the CPU deep-zoom path;
    -- auto-enabled when the renderer switches into it).
    if gpuMode then
        love.graphics.setColor(0, 0, 0, 0.3)
    else
        love.graphics.setColor(0, 0, 0, 0.55)
    end
    love.graphics.rectangle("fill", previewToggleX, previewToggleY, previewToggleW, previewToggleH, 6, 6)
    love.graphics.setColor(1, 1, 1, gpuMode and 0.5 or 1)
    love.graphics.rectangle("line", previewToggleX, previewToggleY, previewToggleW, previewToggleH, 6, 6)
    love.graphics.print("Preview: " .. (previewEnabled and "ON" or "OFF"), previewToggleX + 10, previewToggleY + 10)

    -- Keyboard cheat sheet (bottom right)
    local cheatLines = {
        "W/A/S/D: Pan",
        "Z: Zoom in",
        "X: Zoom out",
        "Esc: Quit",
    }
    local font = love.graphics.getFont()
    local cheatW = 110
    for _, line in ipairs(cheatLines) do
        cheatW = math.max(cheatW, font:getWidth(line) + 20)
    end
    local cheatH = #cheatLines * 20
    local cheatX = width - cheatW - 10
    local cheatY = height - cheatH - 10
    love.graphics.setColor(0.08, 0.08, 0.08, 0.75)
    love.graphics.rectangle("fill", cheatX, cheatY, cheatW, cheatH, 6, 6)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("line", cheatX, cheatY, cheatW, cheatH, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    for i, line in ipairs(cheatLines) do
        love.graphics.print(line, cheatX + 10, cheatY + 5 + (i - 1) * 20)
    end

    -- About button (top right) and expandable about page
    aboutButtonX = width - aboutButtonWidth - 10
    aboutButtonY = 10
    love.graphics.setColor(0.08, 0.08, 0.08, 0.75)
    love.graphics.rectangle("fill", aboutButtonX, aboutButtonY, aboutButtonWidth, aboutButtonHeight, 6, 6)
    love.graphics.setColor(1, 1, 1, aboutOpen and 1 or 0.35)
    love.graphics.rectangle("line", aboutButtonX, aboutButtonY, aboutButtonWidth, aboutButtonHeight, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("About", aboutButtonX + 12, aboutButtonY + 3)

    if aboutOpen then
        local aboutLines = {
            "Mandelbrot Explorer",
            "",
            "A real-time Mandelbrot set explorer.",
            "Standard views render on the GPU;",
            "deep zooms switch to fp64 on the CPU.",
            "",
            "Renderer: " .. renderer,
            "",
            "Built with LÖVE 2D, GLSL and LuaJIT FFI.",
            "License: MIT",
        }
        local fontWidth = 0
        for _, line in ipairs(aboutLines) do
            fontWidth = math.max(fontWidth, font:getWidth(line))
        end
        local pageW = math.max(fontWidth + 20, 260)
        local pageH = #aboutLines * 20 + 14
        local pageX = width - pageW - 10
        local pageY = aboutButtonY + aboutButtonHeight + 10
        love.graphics.setColor(0.05, 0.05, 0.05, 0.85)
        love.graphics.rectangle("fill", pageX, pageY, pageW, pageH, 6, 6)
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.rectangle("line", pageX, pageY, pageW, pageH, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        for i, line in ipairs(aboutLines) do
            love.graphics.print(line, pageX + 10, pageY + 10 + (i - 1) * 20)
        end
    end
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        if x >= statsButtonX and x <= statsButtonX + statsButtonWidth and
           y >= statsButtonY and y <= statsButtonY + statsButtonHeight then
            statsExpanded = not statsExpanded
            return
        end

        if x >= aaToggleX and x <= aaToggleX + aaToggleW and
           y >= aaToggleY and y <= aaToggleY + aaToggleH then
            aaEnabled = not aaEnabled
            if not gpuMode then
                needFullRender = true
            end
            return
        end

        if x >= previewToggleX and x <= previewToggleX + previewToggleW and
           y >= previewToggleY and y <= previewToggleY + previewToggleH then
            previewEnabled = not previewEnabled
            if not previewEnabled and not gpuMode then
                generateFrame(false)
            end
            return
        end

        if x >= aboutButtonX and x <= aboutButtonX + aboutButtonWidth and
           y >= aboutButtonY and y <= aboutButtonY + aboutButtonHeight then
            aboutOpen = not aboutOpen
            return
        end
    end
end
