local width, height = 800, 600

local centerX, centerY = -0.5, 0.0
local baseHalfWidth = 2.5
local baseHalfHeight = 2.0

local period = 10
local maxZoomExponent = 4
local baseIter = 100

local baseAngleSpeed = 0.01

local zoom = 1.0
local angle = 0.0
local max_iter = baseIter

local imageData, mandelbrotImage

function love.load()
    love.window.setMode(width, height)
    imageData = love.image.newImageData(width, height)
    mandelbrotImage = love.graphics.newImage(imageData)
end

local function generateFrame()
    local scale = zoom
    local aspect = width / height
    local xmin = centerX - baseHalfWidth * scale
    local xmax = centerX + baseHalfWidth * scale
    local ymin = centerY - baseHalfHeight * scale
    local ymax = centerY + baseHalfHeight * scale

    for x = 0, width - 1 do
        for y = 0, height - 1 do
            local normX = (x - width/2) / (width/2)
            local normY = (y - height/2) / (height/2)

            local u = normX * (baseHalfWidth * scale)
            local v = normY * (baseHalfHeight * scale)

            local ru = u * math.cos(angle) - v * math.sin(angle)
            local rv = u * math.sin(angle) + v * math.cos(angle)
            
            local cr = centerX + ru
            local ci = centerY + rv

            local zr, zi = 0, 0
            local iter = 0
            while (zr*zr + zi*zi < 4) and (iter < max_iter) do
                local temp = zr*zr - zi*zi + cr
                zi = 2 * zr * zi + ci
                zr = temp
                iter = iter + 1
            end

            local t = iter / max_iter
            local r = 9 * (1 - t) * t^3 * 255
            local g = 15 * (1 - t)^2 * t^2 * 255
            local b = 8.5 * (1 - t)^3 * t * 255

            imageData:setPixel(x, y, r/255, g/255, b/255, 1)
        end
    end
    mandelbrotImage:replacePixels(imageData)
end

function love.update(dt)
    local timeInCycle = love.timer.getTime() % period
    local phase = timeInCycle / period

    zoom = math.exp(-phase * maxZoomExponent)

    max_iter = baseIter + math.floor(-math.log(zoom) * 50)

    angle = angle + baseAngleSpeed * dt

    generateFrame()
end

function love.draw()
    love.graphics.draw(mandelbrotImage, 0, 0)
    love.graphics.print("Zoom: " .. string.format("%.5f", zoom), 10, 10)
    love.graphics.print("Angle: " .. string.format("%.2f", angle), 10, 30)
    love.graphics.print("Max Iterations: " .. max_iter, 10, 50)
    love.graphics.print("Cycle phase: " .. string.format("%.2f", (love.timer.getTime()%period)/period), 10, 70)
end
