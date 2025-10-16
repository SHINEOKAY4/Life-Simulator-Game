--[[ --------------------------------------------------------------------

-- 4thAxis
-- 6/20/22

    MIT License

    Copyright (c) 2022 4thAxis

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]
--------------------------------------------------------------------

local Module = {
	Epsilon = 1e-5,
	CameraAngleX = 0,
	CameraAngleY = 0,
}

--------------------------------------------------------------------
---------------------------  Imports   -----------------------------
--------------------------------------------------------------------

local Configs = require(script.Parent:WaitForChild("Configurations"))

--------------------------------------------------------------------
--------------------------  Services  ------------------------------
--------------------------------------------------------------------

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

--------------------------------------------------------------------
-------------------------  Constants  ------------------------------
--------------------------------------------------------------------

local DOWN_VECTOR = Vector3.new(0, -1, 0)
local UP_VECTOR = Vector3.new(0, 1, 0)

--------------------------------------------------------------------

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local camera = workspace.CurrentCamera
local screenSize = camera.ViewportSize
local screenSizeX, screenSizeY = screenSize.X, screenSize.Y
local pixelCoordinateRatioX, pixelCoordinateRatioY = 1 / screenSizeX, 1 / screenSizeY

local character = player.Character or player.CharacterAdded:Wait()
local head = character:WaitForChild("Head")
local root = character:WaitForChild("HumanoidRootPart")
local torso = character:WaitForChild("UpperTorso")
local neck = head:WaitForChild("Neck")
local waist = torso:WaitForChild("Waist")
local neckOriginC0 = neck.C0
local waistOriginC0 = waist.C0

neck.MaxVelocity = 1 / 3

--------------------------------------------------------------------
--------------------------  Privates  ------------------------------
--------------------------------------------------------------------

local function DisableRobloxCamera()
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

local function GetRotationXY(X, Y)
	X = X or Module.CameraAngleX
	Y = Y or Module.CameraAngleY

	local Cosy, Siny = math.cos(X), math.sin(X)
	local Cosx, Sinx = math.cos(Y), math.sin(Y)
	return CFrame.new(0, 0, 0, Cosy, Siny * Sinx, Siny * Cosx, 0, Cosx, -Sinx, -Siny, Cosy * Sinx, Cosy * Cosx)
end

local function GetPositionToWorldByOffset(OriginCF, XOffset, YOffset, ZOffset)
	-- Perserve rotational matrix, only transform position to world instead rather than naively transforming origin cframe to world space
	XOffset = XOffset or Configs.CamLockOffset.X
	YOffset = YOffset or Configs.CamLockOffset.Y
	ZOffset = ZOffset or Configs.CamLockOffset.Z

	local X, Y, Z, M11, M12, M13, M21, M22, M23, M31, M32, M33 = OriginCF:GetComponents()
	return Vector3.new(
		M11 * XOffset + M12 * YOffset + M13 * ZOffset + X,
		M21 * XOffset + M22 * YOffset + M23 * ZOffset + Y,
		M31 * XOffset + M32 * YOffset + M33 * ZOffset + Z
	)
end

local function FastCFLerpCase(MotorC0, YOffset, Alpha, R11, R12, R13, R21, R22, R23, R31, R32, R33)
	local ax, ay, az, a11, a12, a13, a21, a22, a23, a31, a32, a33 = MotorC0:GetComponents()
	local Determinant = a11 * a22 * a33
		+ a12 * a23 * a31
		+ a13 * a21 * a32
		- a11 * a23 * a32
		- a12 * a21 * a33
		- a13 * a22 * a31
	if Determinant ~= 0 then
		return false
	end -- if det is 0, we don't have to calculute for matrix inverse; shortcut lerp. Otherwise, Roblox here probably benefits from SIMD hardware optimizations which typically use elimination methods. Technically orthogonal matrices shouldn't have det=0 but who said this can't be just used with orthongal matrices ;)
	-- convert goal to start's object space with inversion omitted
	local x, y, z = ax, ay, az
	R11, R12, R13 = 0, 0, a11 * R13 + a12 * R23 + a13 * R33
	R21, R22, R23 = 0, 0, a21 * R13 + a22 * R23 + a23 * R33
	R31, R32, R33 = 0, 0, a31 * R13 + a32 * R23 + a33 * R33

	if R33 > 0 then -- (R11+R22+R33)>0  (our trace)
		local Pos = MotorC0.Position + (Vector3.new(x, y + YOffset, z) - MotorC0.Position) * Alpha * 0.5
		local Theta = math.acos(R23 * (0.5 / (math.sqrt(1 + R33)))) -- possible to cancel out square root
		if Theta == 0 then -- theta~=0 is too expensive to handle because we need c0* matrix from axis angles for rotation and additional stuff if we go with this approach...
			return CFrame.new(Pos.X, Pos.Y, Pos.Z, R11, R12, R13, R21, R22, R23, R31, R32, R33)
		end
	end

	return false
end

local function SlerpXY(Origin, GoalPos, GoalLook, Alpha)
	Alpha = math.clamp(Alpha or 0.5, 0, 1)
	local Theta = math.acos(Origin.lookVector:Dot(GoalLook)) -- LookVector of goal cframe
	if Theta < 0.01 then
		return Origin
	else
		local Position = Origin.Position:Lerp(GoalPos, Alpha)
		local InvSin = 1 / math.sin(Theta)
		local Rotation = math.sin((1 - Alpha) * Theta) * InvSin * Origin.LookVector
			+ math.sin(Alpha * Theta) * InvSin * GoalLook
		return CFrame.lookAt(Position, Position + Rotation)
	end
end

local function TransformMotor(motor, motorOriginC0, x, y, yOffset, alpha)
	yOffset = yOffset or 0
	alpha = alpha or 0.5
	local motorC0 = motor.C0
	-- rotation matrix --
	local cosx, sinx = math.cos(x), math.sin(x)
	local cosy, siny = math.cos(y), math.sin(y)
	local r11, r12, r13 = 0, 0, siny
	local r21, r22, r23 = 0, 0, -cosy * sinx
	local r31, r32, r33 = 0, 0, cosx * cosy
	-- transformation matrix (OriginC0*rotation) --
	local originX, originY, originZ, a11, a12, a13, a21, a22, a23, a31, a32, a33 = motorOriginC0:GetComponents()
	r11, r12, r13 = 0, 0, a11 * r13 + a12 * r23 + a13 * r33
	r21, r22, r23 = 0, 0, a21 * r13 + a22 * r23 + a23 * r33
	r31, r32, r33 = 0, 0, a31 * r13 + a32 * r23 + a33 * r33

	local fromFastLerp = FastCFLerpCase(motorC0, yOffset, alpha, r11, r12, r13, r21, r22, r23, r31, r32, r33) -- calculute for orthongonal matrix -> only rotational matrix
	return fromFastLerp
		or SlerpXY(motor.C0, Vector3.new(originX, originY, originZ), Vector3.new(-r13, -r23, -r33), alpha)
end

local function GetViewMatrix(Eye, Focus)
	-- Faster alternative to cframe.lookat for our case since we are more commonly prone to special cases such as: when focus is facing up/down or if focus and eye are colinear vectors
	local XAxis = Focus - Eye -- Lookvector
	if XAxis:Dot(XAxis) <= Module.Epsilon then
		return CFrame.new(Eye.X, Eye.Y, Eye.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	XAxis = XAxis.Unit
	local Xx, Xy, Xz = XAxis.X, XAxis.Y, XAxis.Z
	local RNorm = ((Xz * Xz) + (Xx * Xx)) -- R:Dot(R), our right vector
	if RNorm <= Module.Epsilon and math.abs(XAxis.Y) > 0 then
		return CFrame.fromMatrix(Eye, -math.sign(XAxis.Y) * Vector3.zAxis, Vector3.xAxis)
	end
	RNorm = 1 / (RNorm ^ 0.5) -- take the root of our squared norm and inverse division
	local Rx, Rz = -(Xz * RNorm), (Xx * RNorm) -- cross y-axis with right and normalize
	local Ux, Uy, Uz = -Rz * (Rz * Xx - Rx * Xz), -(Rz * Rz) * Xy - (Rx * Rx) * Xy, Rx * (Rz * Xx - Rx * Xz) -- cross right and up and normalize.
	local UNorm = 1 / ((Ux * Ux) + (Uy * Uy) + (Uz * Uz)) ^ 0.5 -- inverse division and multiply this ratio rather than dividing each component
	return CFrame.new(
		Eye.X,
		Eye.Y,
		Eye.Z,
		Rx,
		-Xy * Rz,
		Ux * UNorm,
		0,
		(Rz * Xx) - Rx * Xz,
		Uy * UNorm,
		Rz,
		Xy * Rx,
		Uz * UNorm
	)
end

--------------------------------------------------------------------
-------------------------  Functions  ------------------------------
--------------------------------------------------------------------

Module.OverTheShoulder = function(_, cameraAngleX, cameraAngleY)
	Module.CameraAngleX = cameraAngleX or Module.CameraAngleX
	Module.CameraAngleY = cameraAngleY or Module.CameraAngleY
	DisableRobloxCamera()

	local origin = CFrame.new(root.Position)
		* GetRotationXY(math.rad(Module.CameraAngleX), math.rad(Module.CameraAngleY))
	local eye = GetPositionToWorldByOffset(origin)
	local focus = GetPositionToWorldByOffset(origin, Configs.CamLockOffset.X, Configs.CamLockOffset.Y, -10000)

	camera.CFrame = GetViewMatrix(eye, focus)
end

Module.IsometricCamera = function(_, cameraDepth, heightOffset, fov)
	cameraDepth = cameraDepth or Configs.IsometricCameraDepth
	heightOffset = heightOffset or Configs.IsometricHeightOffset
	camera.FieldOfView = fov or Configs.IsometricFieldOfView
	DisableRobloxCamera()

	local focus = root.Position + Vector3.new(0, heightOffset, 0)
	local eye = focus + Vector3.new(cameraDepth, cameraDepth, cameraDepth)
	camera.CFrame = GetViewMatrix(eye, focus)
end

Module.SideScrollingCamera = function(_, cameraDepth, heightOffset, fov)
	cameraDepth = cameraDepth or Configs.SideCameraDepth
	heightOffset = heightOffset or Configs.SideHeightOffset
	camera.FieldOfView = fov or Configs.SideFieldOfView
	DisableRobloxCamera()

	local focus = root.Position + Vector3.new(0, heightOffset, 0)
	local eye = Vector3.new(focus.X, focus.Y, cameraDepth)
	camera.CFrame = GetViewMatrix(eye, focus)
end

Module.TopDownCamera = function(_, faceMouse, mouseSensitivity, offset, direction, distance)
	faceMouse = faceMouse or Configs.TopDownFaceMouse
	mouseSensitivity = mouseSensitivity or Configs.TopDownMouseSensitivity
	distance = distance or Configs.TopDownDistance
	direction = direction or DOWN_VECTOR
	offset = offset or Configs.TopDownOffset
	DisableRobloxCamera()

	local cursor = UserInputService:GetMouseLocation()
	local axis = Vector3.new(
		-((cursor.Y - screenSizeY * 0.5) * pixelCoordinateRatioY),
		0,
		((cursor.X - screenSizeX * 0.5) * pixelCoordinateRatioX)
	)

	local eye = (distance + (root.Position + offset)) + axis * mouseSensitivity
	local focus = eye + direction
	camera.CFrame = GetViewMatrix(eye, focus)

	if faceMouse then
		local forward = (root.Position - mouse.Hit.Position).Unit
		local rightVector = Vector3.new(-forward.Z, 0, forward.X) -- Forward:Cross(YAxis)
		root.CFrame = CFrame.fromMatrix(root.Position, -rightVector, UP_VECTOR)
	end
end

Module.HeadFollowCamera = function(_, alpha)
	if not (camera.CameraSubject:IsDescendantOf(character) or camera.CameraSubject:IsDescendantOf(player)) then
		return
	end
	alpha = alpha or Configs.HeadFollowAlpha
	local zColumn = -camera.CFrame.LookVector
	zColumn -= Vector3.new(0, zColumn.Y, 0)
	local xColumn = UP_VECTOR:Cross(zColumn)

	if torso.CFrame:PointToObjectSpace(head.Position + zColumn).Z > 0 then
		neck.C0 = neck.C0:Lerp(neckOriginC0 * CFrame.fromMatrix(Vector3.zero, xColumn, UP_VECTOR, zColumn), alpha)
		waist.C0 =
			waist.C0:Lerp(waistOriginC0 * CFrame.fromMatrix(Vector3.zero, xColumn * 0.5, UP_VECTOR, zColumn), alpha)
	end
end

Module.FaceCharacterToMouse = function(_, alpha, goalCFrame)
	goalCFrame = goalCFrame
		or GetViewMatrix(root.Position, Vector3.new(mouse.Hit.Position.X, root.Position.Y, mouse.Hit.Position.Z))
	root.CFrame = root.CFrame:Lerp(goalCFrame, alpha or Configs.FaceCharacterAlpha)
end

Module.FollowMouse = function(_, alpha, xOffset, yOffset)
	alpha = alpha or Configs.MouseAlpha
	xOffset = xOffset or Configs.MouseXOffset
	yOffset = yOffset or Configs.MouseYOffset
	DisableRobloxCamera()

	local easing = Configs.MouseCameraEasingStyle
		and TweenService:GetValue(
			Configs.MouseCameraSmoothness,
			Configs.MouseCameraEasingStyle,
			Configs.MouseCameraEasingDirection or Enum.EasingDirection.Out
		)
	local goal = head.CFrame
		* CFrame.new(0, Configs.AspectRatio.Y, Configs.AspectRatio.X)
		* GetRotationXY(xOffset, math.rad(yOffset))
	if easing then
		camera.CFrame = camera.CFrame:Lerp(goal, easing)
	else
		local smoothness = Configs.MouseCameraSmoothness - 1
		camera.CFrame = camera.CFrame:Lerp(goal, (smoothness ^ 5) + 1)
	end

	local targetPosition = mouse.Hit.Position
	local distance = (head.CFrame.Position - targetPosition).Magnitude
	local difference = head.CFrame.Y - targetPosition.Y
	local xAngle = -math.atan(difference / distance) * 0.5
	local yAngle = ((head.CFrame.Position - targetPosition).Unit:Cross(torso.CFrame.LookVector)).Y

	neck.C0 = TransformMotor(neck, neckOriginC0, xAngle, yAngle, 1, 0.5)
	waist.C0 = TransformMotor(waist, waistOriginC0, xAngle, yAngle * 0.5, 0, 0.5)
end

return Module
