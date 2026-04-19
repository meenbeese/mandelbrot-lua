local ffi = require("ffi")

ffi.cdef[[
    void generate_mandelbrot(uint8_t* pixels, int width, int height,
                             double centerX, double centerY, double zoom,
                             int max_iter, int threads);
    int get_thread_count();
]]

local libname
if jit.os == "Windows" then
    libname = "mandelbrot.dll"
elseif jit.os == "OSX" then
    libname = "mandelbrot.dylib"
else
    libname = "mandelbrot.so"
end

local path = love.filesystem.getSource() .. "/" .. libname

local mandelbrotLib = ffi.load(path)

local width, height = 800, 600
local max_iter = 100

-- View parameters
local centerX, centerY = -0.5, 0.0
local zoom = 1.0
local baseHalfWidth = 2.5
local baseHalfHeight = 2.0

-- Control speeds
local panSpeed = 1.0
local isZoomingOrPanning = false

local imageData, mandelbrotImage

local threadCount

local previewScale = 3
local previewWidth, previewHeight
local previewScaleX, previewScaleY
local previewImageData, previewImage
local previewEnabled = true
local isPreviewActive = false
local lastInteractionTime = 0
local idleRenderDelay = 0.1
local needFullRender = false

-- UI state
local statsExpanded = true
local statsButtonX, statsButtonY = 10, 10
local statsButtonWidth, statsButtonHeight = 20, 20
local previewToggleX, previewToggleY = 10, 0
local previewToggleW, previewToggleH = 190, 30

local shader

function love.load()
    love.window.setMode(0, 0, { fullscreen = true })
    width, height = love.graphics.getDimensions()

    threadCount = mandelbrotLib.get_thread_count()

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

function generateFrame(usePreview)
    local targetWidth = usePreview and previewWidth or width
    local targetHeight = usePreview and previewHeight or height
    local pixelCount = targetWidth * targetHeight * 4
    local buffer = ffi.new("uint8_t[?]", pixelCount)
    local renderIter = max_iter

    mandelbrotLib.generate_mandelbrot(buffer, targetWidth, targetHeight, centerX, centerY, zoom, renderIter, threadCount)

    local targetData = usePreview and previewImageData or imageData
    local pixelPtr = targetData:getFFIPointer()
    ffi.copy(pixelPtr, buffer, pixelCount)

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

local function computeIterations()
    local safeZoom = math.max(zoom, 1e-10)
    local calculated = 100 + math.floor(math.log(safeZoom) * 50)
    local limit = zoom > 1 and 2000 or 300
    return math.max(50, math.min(calculated, limit))
end

function love.update(dt)
    local moveAmount = panSpeed * (baseHalfWidth / zoom) * dt
    local zoomSpeed = 1.05  -- Zoom 5% per zoom action

    isZoomingOrPanning = false

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

    if isZoomingOrPanning then
        lastInteractionTime = love.timer.getTime()
        max_iter = computeIterations()
        if previewEnabled then
            generateFrame(true)
        else
            generateFrame(false)
        end
    else
        if previewEnabled and needFullRender and love.timer.getTime() - lastInteractionTime > idleRenderDelay then
            generateFrame(false)
        end
    end
end

function love.draw()
    love.graphics.setShader(shader)
    if isPreviewActive then
        love.graphics.draw(previewImage, 0, 0, 0, previewScaleX, previewScaleY)
    else
        love.graphics.draw(mandelbrotImage, 0, 0)
    end
    love.graphics.setShader()

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
        love.graphics.setColor(1, 1, 1, 1)
        local statsX = statsButtonX + statsButtonWidth + 10
        local zoomPower = math.log10(math.max(zoom, 1e-10))
        love.graphics.print("Center: (" .. string.format("%.5f", centerX) ..
                            ", " .. string.format("%.5f", centerY) .. ")", statsX, 10)
        love.graphics.print("Zoom: 10^" .. string.format("%.2f", zoomPower), statsX, 30)
        love.graphics.print("Max Iterations: " .. max_iter, statsX, 50)
        love.graphics.print("Threads: " .. tostring(threadCount), statsX, 70)
        love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), statsX, 90)
    end

    previewToggleY = height - previewToggleH - 10
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", previewToggleX, previewToggleY, previewToggleW, previewToggleH, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("line", previewToggleX, previewToggleY, previewToggleW, previewToggleH, 6, 6)
    love.graphics.print("Preview: " .. (previewEnabled and "ON" or "OFF"), previewToggleX + 10, previewToggleY + 10)
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

        if x >= previewToggleX and x <= previewToggleX + previewToggleW and
           y >= previewToggleY and y <= previewToggleY + previewToggleH then
            previewEnabled = not previewEnabled
            if not previewEnabled then
                generateFrame(false)
            end
        end
    end
end
