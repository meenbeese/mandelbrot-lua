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

function love.load()
    love.window.setMode(0, 0, { fullscreen = true })
    width, height = love.graphics.getDimensions()

    threadCount = mandelbrotLib.get_thread_count()

    imageData = love.image.newImageData(width, height)
    mandelbrotImage = love.graphics.newImage(imageData)
    generateFrame()
end

function generateFrame()
    local pixelCount = width * height * 4
    local buffer = ffi.new("uint8_t[?]", pixelCount)

    mandelbrotLib.generate_mandelbrot(buffer, width, height, centerX, centerY, zoom, max_iter, threadCount)

    local pixelPtr = imageData:getFFIPointer()
    ffi.copy(pixelPtr, buffer, pixelCount)

    mandelbrotImage:replacePixels(imageData)
end

local function computeIterations()
    local safeZoom = math.max(zoom, 1e-10)
    local calculated = 100 + math.floor(-math.log(safeZoom) * 50)
    local limit = zoom > 1 and 300 or 2000  -- cap for zoomed-out
    return math.max(50, math.min(calculated, limit))
end

function love.update(dt)
    local moveAmount = panSpeed * zoom * baseHalfWidth * dt
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
        max_iter = computeIterations()
        generateFrame()
    end
end

function love.draw()
    love.graphics.draw(mandelbrotImage, 0, 0)
    love.graphics.print("Center: (" .. string.format("%.5f", centerX) ..
                        ", " .. string.format("%.5f", centerY) .. ")", 10, 10)
    love.graphics.print("Zoom: " .. string.format("%.10f", zoom), 10, 30)
    love.graphics.print("Max Iterations: " .. max_iter, 10, 50)
    love.graphics.print("Threads: " .. tostring(threadCount), 10, 70)
    love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), 10, 90)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
