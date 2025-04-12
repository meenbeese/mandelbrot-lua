local width, height = 800, 600
local max_iter = 100

-- View parameters
local centerX, centerY = -0.5, 0.0
local zoom = 1.0
local baseHalfWidth = 2.5
local baseHalfHeight = 2.0

-- Control speeds
local panSpeed = 1.0
local zoomSpeedFactor = 0.98

local imageData, mandelbrotImage

function love.load()
    love.window.setMode(width, height)
    imageData = love.image.newImageData(width, height)
    mandelbrotImage = love.graphics.newImage(imageData)
    generateFrame()
end

function generateFrame()
    local scale = zoom
    local aspect = width / height
    local xmin = centerX - baseHalfWidth * scale
    local xmax = centerX + baseHalfWidth * scale
    local ymin = centerY - baseHalfHeight * scale
    local ymax = centerY + baseHalfHeight * scale

    for x = 0, width - 1 do
        for y = 0, height - 1 do
            local cr = xmin + (x / width) * (xmax - xmin)
            local ci = ymin + (y / height) * (ymax - ymin)
            local zr, zi = 0, 0
            local iter = 0
            while (zr * zr + zi * zi < 4) and (iter < max_iter) do
                local temp = zr * zr - zi * zi + cr
                zi = 2 * zr * zi + ci
                zr = temp
                iter = iter + 1
            end

            local t = iter / max_iter
            local r = 9 * (1 - t) * t^3 * 255
            local g = 15 * (1 - t)^2 * t^2 * 255
            local b = 8.5 * (1 - t)^3 * t * 255
            imageData:setPixel(x, y, r / 255, g / 255, b / 255, 1)
        end
    end
    mandelbrotImage:replacePixels(imageData)
end

function love.update(dt)
    local moveAmount = panSpeed * zoom * baseHalfWidth * dt

    if love.keyboard.isDown('w') then
        centerY = centerY - moveAmount
    end
    if love.keyboard.isDown('s') then
        centerY = centerY + moveAmount
    end
    if love.keyboard.isDown('a') then
        centerX = centerX - moveAmount
    end
    if love.keyboard.isDown('d') then
        centerX = centerX + moveAmount
    end

    if love.keyboard.isDown('z') then
        zoom = zoom * zoomSpeedFactor
    end
    if love.keyboard.isDown('x') then
        zoom = zoom / zoomSpeedFactor
    end

    max_iter = 100 + math.floor(-math.log(zoom) * 50)

    generateFrame()
end

function love.draw()
    love.graphics.draw(mandelbrotImage, 0, 0)
    love.graphics.print("Center: (" .. string.format("%.5f", centerX) ..
                        ", " .. string.format("%.5f", centerY) .. ")", 10, 10)
    love.graphics.print("Zoom: " .. string.format("%.5f", zoom), 10, 30)
    love.graphics.print("Max Iterations: " .. max_iter, 10, 50)
end
