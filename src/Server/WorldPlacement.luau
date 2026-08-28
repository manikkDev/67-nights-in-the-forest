local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local WorldPlacement = {}

export type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

export type Reservation = {
	position: Vector3,
	radius: number,
	category: string,
}

local reservations: { Reservation } = {}

local function flatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

function WorldPlacement.Hash(text: string): number
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 16777619) % 2147483647
	end
	return math.max(1, hash)
end

function WorldPlacement.Reset()
	table.clear(reservations)
end

function WorldPlacement.Reserve(position: Vector3, radius: number, category: string)
	table.insert(reservations, {
		position = position,
		radius = radius,
		category = category,
	})
end

function WorldPlacement.IsReserved(position: Vector3, radius: number): boolean
	for _, reservation in ipairs(reservations) do
		if flatDistance(position, reservation.position) < radius + reservation.radius then
			return true
		end
	end
	return false
end

function WorldPlacement.GetGroundCFrame(groundPart: BasePart, position: Vector3, yaw: number?): (CFrame?, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { groundPart }
	local origin = Vector3.new(position.X, groundPart.Position.Y + groundPart.Size.Y * 0.5 + 500, position.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
	local groundPosition = if result
		then result.Position
		else Vector3.new(position.X, groundPart.Position.Y + groundPart.Size.Y * 0.5, position.Z)
	return CFrame.new(groundPosition) * CFrame.Angles(0, yaw or 0, 0), Vector3.yAxis
end

function WorldPlacement.IsFootprintFree(cframe: CFrame, footprint: Vector3, exclusions: { Instance }?): boolean
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclusions or {}
	overlap.MaxParts = 40
	for _, part in ipairs(Workspace:GetPartBoundsInBox(cframe, footprint, overlap)) do
		local parent = part.Parent
		local isExpandedGround = parent and parent.Name == "ExpandedGround" and part:GetAttribute("ExpansionGenerated") == true
		if part:IsA("BasePart") and part.Transparency < 0.98 and not isExpandedGround then
			return false
		end
	end
	return true
end

function WorldPlacement.IsPathAccessible(from: Vector3, to: Vector3): boolean
	local path = PathfindingService:CreatePath({
		AgentRadius = 3,
		AgentHeight = 6,
		AgentCanJump = true,
		WaypointSpacing = 8,
	})
	local success = pcall(function()
		path:ComputeAsync(from, to)
	end)
	return success and path.Status == Enum.PathStatus.Success
end

function WorldPlacement.FindPosition(options: {
	center: Vector3,
	groundPart: BasePart,
	bounds: Bounds,
	minDistance: number,
	maxDistance: number,
	footprint: Vector3,
	clearanceRadius: number,
	seed: number,
	exclusions: { Instance }?,
	maxRetries: number?,
	maxSlope: number?,
	requirePathFrom: Vector3?,
	faceCenter: boolean?,
}): CFrame?
	local random = Random.new(options.seed)
	local retries = options.maxRetries or 64
	for attempt = 1, retries do
		local angle = if attempt <= retries * 0.75
			then random:NextNumber(0, math.pi * 2)
			else (attempt * 2.399963229728653)
		local distance = random:NextNumber(options.minDistance, options.maxDistance)
		local position = options.center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local halfX = options.footprint.X * 0.5
		local halfZ = options.footprint.Z * 0.5
		if position.X - halfX < options.bounds.minX
			or position.X + halfX > options.bounds.maxX
			or position.Z - halfZ < options.bounds.minZ
			or position.Z + halfZ > options.bounds.maxZ
		then
			continue
		end
		if WorldPlacement.IsReserved(position, options.clearanceRadius) then
			continue
		end
		local yaw = if options.faceCenter then math.atan2(options.center.X - position.X, options.center.Z - position.Z) else random:NextNumber(0, math.pi * 2)
		local groundCFrame, normal = WorldPlacement.GetGroundCFrame(options.groundPart, position, yaw)
		if not groundCFrame or not normal then
			continue
		end
		local slope = math.deg(math.acos(math.clamp(normal:Dot(Vector3.yAxis), -1, 1)))
		if slope > (options.maxSlope or 20) then
			continue
		end
		local checkCFrame = groundCFrame * CFrame.new(0, options.footprint.Y * 0.5, 0)
		local exclusions = table.clone(options.exclusions or {})
		table.insert(exclusions, options.groundPart)
		if not WorldPlacement.IsFootprintFree(checkCFrame, options.footprint, exclusions) then
			continue
		end
		if options.requirePathFrom and not WorldPlacement.IsPathAccessible(options.requirePathFrom, groundCFrame.Position) then
			continue
		end
		return groundCFrame
	end
	return nil
end

return WorldPlacement
