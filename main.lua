local ffi = require("ffi")

ffi.cdef[[
    void generate_mandelbrot(uint8_t* pixels, int width, int height,
                             double centerX, double centerY,
                             double zoom, int max_iter);
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

function love.load()
    love.window.setMode(0, 0, { fullscreen = true })
    width, height = love.graphics.getDimensions()

    imageData = love.image.newImageData(width, height)
    mandelbrotImage = love.graphics.newImage(imageData)
    generateFrame()
end

function generateFrame()
    local pixelCount = width * height * 4
    local buffer = ffi.new("uint8_t[?]", pixelCount)

    mandelbrotLib.generate_mandelbrot(buffer, width, height, centerX, centerY, zoom, max_iter)

    for x = 0, width - 1 do
        for y = 0, height - 1 do
            local i = (y * width + x) * 4
            local r = buffer[i] / 255
            local g = buffer[i + 1] / 255
            local b = buffer[i + 2] / 255
            local a = buffer[i + 3] / 255
            imageData:setPixel(x, y, r, g, b, a)
        end
    end

    mandelbrotImage:replacePixels(imageData)
end

function love.update(dt)
    local moveAmount = panSpeed * zoom * baseHalfWidth * dt
    local zoomSpeed = 0.05

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
        zoom = zoom * (1 + zoomSpeed)
        isZoomingOrPanning = true
    end
    if love.keyboard.isDown('x') then
        zoom = zoom / (1 + zoomSpeed)
        isZoomingOrPanning = true
    end

    if isZoomingOrPanning then
        max_iter = 100 + math.floor(-math.log(zoom) * 50)
        generateFrame()
    end
end

function love.draw()
    love.graphics.draw(mandelbrotImage, 0, 0)
    love.graphics.print("Center: (" .. string.format("%.5f", centerX) ..
                        ", " .. string.format("%.5f", centerY) .. ")", 10, 10)
    love.graphics.print("Zoom: " .. string.format("%.5f", zoom), 10, 30)
    love.graphics.print("Max Iterations: " .. max_iter, 10, 50)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
