local MOD_TAG = "[BloodSplatterBoth]"

local function log(message)
    print(string.format("%s %s\n", MOD_TAG, message))
end

local function unwrap(parameter)
    if parameter == nil then
        return nil
    end

    local succeeded, value = pcall(function()
        return parameter:get()
    end)

    if succeeded then
        return value
    end
    return parameter
end

-- Class ancestry helpers (cached by UClass address)
local classAncestryCache = {}
local classAncestryCacheCount = 0

local function getClassAncestryNames(class)
    if not class or not class:IsValid() then
        return {}
    end

    local key = nil
    local okKey = pcall(function()
        key = class:GetAddress()
    end)

    if okKey and key then
        local known = classAncestryCache[key]
        if known ~= nil then
            return known
        end
    end

    local names = {}
    local walk = class
    for _ = 1, 64 do
        if not walk or not walk:IsValid() then
            break
        end
        local ok, name = pcall(function()
            return walk:GetFName():ToString()
        end)
        if ok and name then
            names[#names + 1] = name
        end
        walk = walk:GetSuperStruct()
    end

    if okKey and key then
        if classAncestryCacheCount > 512 then
            classAncestryCache = {}
            classAncestryCacheCount = 0
        end
        classAncestryCache[key] = names
        classAncestryCacheCount = classAncestryCacheCount + 1
    end

    return names
end

local function ancestryContains(names, target)
    for i = 1, #names do
        if names[i] == target then
            return true
        end
    end
    return false
end

local function ancestryContainsAny(names, targets)
    for i = 1, #names do
        if targets[names[i]] then
            return true
        end
    end
    return false
end

local HUMAN_NPC_BASES = {
    BP_NPC_NewBase_C = true,
}

local PLAYER_BASES = {
    PalPlayerCharacter = true,
    BP_PalPlayerCharacter_C = true,
}

-- Live pal actors inherit native PalCharacter (or common monster BP bases).
-- Players also inherit PalCharacter, so always exclude PLAYER_BASES first.
local PAL_CREATURE_BASES = {
    PalCharacter = true,
    BP_MonsterBase_C = true,
    BP_PalMonsterBase_C = true,
}

local function isHumanNPC(actor)
    if not actor or not actor:IsValid() then
        return false
    end

    local class = actor:GetClass()
    if not class or not class:IsValid() then
        return false
    end

    return ancestryContainsAny(getClassAncestryNames(class), HUMAN_NPC_BASES)
end

local function isPlayerCharacter(actor)
    if not actor or not actor:IsValid() then
        return false
    end

    local class = actor:GetClass()
    if not class or not class:IsValid() then
        return false
    end

    return ancestryContainsAny(getClassAncestryNames(class), PLAYER_BASES)
end

local function isPalCreature(actor)
    if not actor or not actor:IsValid() then
        return false
    end

    if isHumanNPC(actor) or isPlayerCharacter(actor) then
        return false
    end

    local class = actor:GetClass()
    if not class or not class:IsValid() then
        return false
    end

    return ancestryContainsAny(getClassAncestryNames(class), PAL_CREATURE_BASES)
end

local function isBloodEligible(actor)
    return isHumanNPC(actor) or isPalCreature(actor)
end

local cachedBloodFXModActor = nil

local cachedModActorPath = nil
local cachedModActorWorldName = nil

local function getWorldFullName(object)
    if not object or not object:IsValid() then
        return nil
    end

    local succeeded, name = pcall(function()
        local world = object:GetWorld()
        if world and world:IsValid() then
            return world:GetFullName()
        end
        return nil
    end)

    return succeeded and name or nil
end

local MODACTOR_RETRY_INTERVAL = 5.0
local lastModActorSearchTime = nil
local modActorMissingLogged = false

local function nowSeconds()
    return os.time()
end

local function findBloodFXModActor(worldContext)
    local targetWorldName = getWorldFullName(worldContext)

    if cachedBloodFXModActor and cachedBloodFXModActor:IsValid() then
        local cachedWorldName = cachedModActorWorldName
        if cachedWorldName and (not targetWorldName or cachedWorldName == targetWorldName) then
            return cachedBloodFXModActor
        end
    end

    cachedBloodFXModActor = nil
    cachedModActorPath = nil
    cachedModActorWorldName = nil

    local now = nowSeconds()
    if lastModActorSearchTime ~= nil then
        if now - lastModActorSearchTime < MODACTOR_RETRY_INTERVAL then
            return nil
        end
    end
    lastModActorSearchTime = now

    local actors = FindAllOf("ModActor_C")
    if not actors then
        if not modActorMissingLogged then
            modActorMissingLogged = true
            log("BRIDGE: ModActor_C が1つも見つかりません。"
                .. "このレベルでは血の表現が出ません。"
                .. string.format("再検索は%d秒おきに行います。",
                    MODACTOR_RETRY_INTERVAL))
        end
        return nil
    end

    for _, actor in pairs(actors) do
        if actor and actor:IsValid() then
            local class = actor:GetClass()
            local className = class and class:IsValid() and class:GetFullName() or ""

            if string.find(className, "/Game/Mods/BloodFX/ModActor.ModActor_C", 1, true) then
                local actorWorldName = getWorldFullName(actor)
                if actorWorldName and (not targetWorldName or actorWorldName == targetWorldName) then
                    cachedBloodFXModActor = actor
                    cachedModActorWorldName = actorWorldName

                    local fullName = actor:GetFullName()
                    cachedModActorPath =
                        string.match(fullName, "^%S+%s+(.+)$") or fullName

                    log(string.format("BRIDGE: ModActor cached=%s", fullName))
                    return actor
                end
            end
        end
    end

    return nil
end

local function snapshotVector(vector)
    if not vector then
        return { X = 0.0, Y = 0.0, Z = 0.0 }
    end

    local succeeded, copied = pcall(function()
        return { X = vector.X, Y = vector.Y, Z = vector.Z }
    end)

    return succeeded and copied or { X = 0.0, Y = 0.0, Z = 0.0 }
end

local SPATTER = {
    Enabled       = true,

    -- 1.0.5: keep deferral; drop hit Niagara (AV vector); ground decals only.
    Count         = 2,

    PalHitSpatter = true,

    -- Hit Niagara attached/spawned through UE4SS is the main AV source.
    ImpactFxEnabled = false,

    GroundOnly    = true,

    GroundFromCapsule = true,

    GroundDepth   = 60.0,

    WallDecals    = false,

    WallOnlyOnHeadshot = true,

    WallViaBP = false,

    WallCount     = 1,
    WallRange     = 400.0,
    WallSpread    = 35.0,
    WallDepth     = 30.0,

    WallDecalRoll = 180.0,

    HeadshotWallScale = 2.0,

    SpreadInterval = 0.0,

    MinIntervalPerActor = 0.85,
    MinIntervalPerPal = 1.25,

    HeadshotBypassThrottle = false,
    ConeDegrees   = 35.0,
    StartOffset   = 10.0,

    RangeMin      = 30.0,
    RangeMax      = 220.0,
    FallHeight    = 250.0,

    SizeMin       = 30.0,
    SizeMax       = 80.0,
    Depth         = 16.0,

    LifeSpan      = 120.0,

    FadeScreenSize = 0.005,

    DecalRoll     = 0.0,

    DecalRollByName = {
        ["MI_BloodDecal_10"] = 180.0,
        ["MI_BloodDecal_11"] = 180.0,
    },

    FadeDuration  = 2.0,
    DelayMin      = 0.05,
    DelayMax      = 0.25,

    AttachToBone  = false,

    FxPooling     = 1,

    ImpactFxInterval = 0.35,

    FixedImpactBone = "spine_02",

    ImpactFxTowardAttacker = false,

    ForwardRatio  = 0.5,

    GlobalMaxPerSecond = 6,
}

local IMPACT_BONES = {
    "pelvis", "spine_02", "neck_01", "head",
    "upperarm_l", "upperarm_r", "thigh_l", "thigh_r",
}

local BODY_BLOOD = {

    Enabled = false,

    Radius  = 12.0,

    MaxHits = 12,

    Color = { R = 0.35, G = 0.04, B = 0.03 },

    Alpha   = 0.9,

    Hardness = 0.95,

    TexCutoff   = 0.12,
    TexSoftness = 0.02,

    RejectDistance = 100.0,

    SkipBones = { head = true, eyes_l = true, eyes_r = true },

    DebugLog = false,

    DebugProbe = false,

    DebugRefDump = false,
}

local BODY_BLOOD_BONE_SET = {}
for _, name in ipairs({
    "pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l",
    "upperarm_l", "lowerarm_l", "hand_l", "index_01_l", "index_02_l", "index_03_l",
    "middle_01_l", "middle_02_l", "middle_03_l", "pinky_01_l", "pinky_02_l", "pinky_03_l",
    "ring_01_l", "ring_02_l", "ring_03_l", "thumb_01_l", "thumb_02_l", "thumb_03_l",
    "lowerarm_twist_01_l", "upperarm_twist_01_l", "neck_01", "head", "eyes_l",
    "eyes_r", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "index_01_r",
    "index_02_r", "index_03_r", "middle_01_r", "middle_02_r", "middle_03_r", "pinky_01_r",
    "pinky_02_r", "pinky_03_r", "ring_01_r", "ring_02_r", "ring_03_r", "thumb_01_r",
    "thumb_02_r", "thumb_03_r", "lowerarm_twist_01_r", "upperarm_twist_01_r", "thigh_l",
    "calf_l", "calf_twist_01_l", "foot_l", "ball_l", "thigh_twist_01_l", "thigh_r",
    "calf_r", "calf_twist_01_r", "foot_r", "ball_r", "thigh_twist_01_r",
}) do
    BODY_BLOOD_BONE_SET[name] = true
end

local bodyBloodNextIndex = {}
local bodyBloodActorCount = 0

local refPoseComponentCache = {}
local refPoseMeshCount = 0

local cachedSkelMeshCompClass = nil

local boneFNameCache = {}
local function boneFName(boneName)
    local cached = boneFNameCache[boneName]
    if cached == nil then
        cached = FName(boneName)
        boneFNameCache[boneName] = cached
    end
    return cached
end

local function meshHasSocket(mesh, boneName)
    if not mesh or not mesh:IsValid() or not boneName then
        return false
    end

    local ok, exists = pcall(function()
        return mesh:DoesSocketExist(boneFName(boneName))
    end)
    return ok and exists == true
end

local function getSocketLocationOrNil(mesh, boneName)
    if not meshHasSocket(mesh, boneName) then
        return nil
    end

    local ok, boneLocation = pcall(function()
        return mesh:GetSocketLocation(boneFName(boneName))
    end)
    if ok and boneLocation then
        return snapshotVector(boneLocation)
    end
    return nil
end

local function getActorLocationSnapshot(actor)
    if not actor or not actor:IsValid() then
        return { X = 0.0, Y = 0.0, Z = 0.0 }
    end

    local ok, location = pcall(function()
        return actor:K2_GetActorLocation()
    end)
    if ok and location then
        return snapshotVector(location)
    end
    return { X = 0.0, Y = 0.0, Z = 0.0 }
end

local function findNearestBoneName(mesh, point)
    if not mesh or not mesh:IsValid() then
        return nil
    end

    local bestName, bestDistance = nil, nil
    for _, boneName in ipairs(IMPACT_BONES) do
        if meshHasSocket(mesh, boneName) then
            local ok, boneLocation = pcall(function()
                return mesh:GetSocketLocation(boneFName(boneName))
            end)
            if ok and boneLocation then
                local dx = point.X - boneLocation.X
                local dy = point.Y - boneLocation.Y
                local dz = point.Z - boneLocation.Z
                local d = dx * dx + dy * dy + dz * dz
                if bestDistance == nil or d < bestDistance then
                    bestName, bestDistance = boneName, d
                end
            end
        end
    end
    return bestName
end

local scheduleQueue = {}
local lastPumpTick = 0
local pumpRunning = false
local pumpGeneration = 0

-- Forward decls: runOnGameThread must defer via Schedule/EnsurePumpAlive.
local Schedule
local EnsurePumpAlive

-- Never run FX inline inside native UE4SS hooks (MulticastDamageReact etc.).
-- Sync UObject calls there cause native AVs that Lua pcall cannot catch.
local function runOnGameThread(callback)
    EnsurePumpAlive()
    Schedule(0.05, function()
        local succeeded, errorMessage = pcall(callback)
        if not succeeded then
            log(string.format("GAMETHREAD ERROR: %s", tostring(errorMessage)))
        end
    end)
end

local function stillValid(object)
    local ok, valid = pcall(function()
        return object ~= nil and object:IsValid()
    end)
    return ok and valid
end

local function objectSoftPath(object)
    if not object then
        return nil
    end
    local path = nil
    pcall(function()
        local fullName = object:GetFullName()
        if fullName then
            path = string.match(fullName, "^%S+%s+(.+)$") or fullName
        end
    end)
    return path
end

local function resolveByPath(path)
    if not path then
        return nil
    end
    local ok, found = pcall(function()
        return StaticFindObject(path)
    end)
    if not ok or not found or not stillValid(found) then
        return nil
    end
    return found
end

local PUMP_INTERVAL = 0.15
local PUMP_INTERVAL_MS = 150

local pumpTicks = 0
local lastPumpRestartAt = 0

-- Several deferred FX jobs per tick so combat does not stall the queue.
local SCHEDULE_MAX_PER_TICK = 4

local SCHEDULE_TICK_STRIDE = 1

-- os.time() is 1s resolution; only treat the pump as dead after a long gap.
local PUMP_DEAD_SECONDS = 15

Schedule = function(delaySeconds, callback)
    local ticks = math.ceil((delaySeconds or 0.0) / PUMP_INTERVAL)
    if ticks < 1 then
        ticks = 1
    end
    scheduleQueue[#scheduleQueue + 1] = {
        dueTick = pumpTicks + ticks,
        run = callback,
    }
end

local function pumpSchedule()
    pumpTicks = pumpTicks + 1
    lastPumpTick = nowSeconds()
    if #scheduleQueue == 0 then
        return
    end

    if SCHEDULE_TICK_STRIDE > 1 then
        if (pumpTicks % SCHEDULE_TICK_STRIDE) ~= 0 then
            return
        end
    end

    local remaining = {}
    local ran = 0
    for _, item in ipairs(scheduleQueue) do

        local canRun = false
        if pumpTicks >= item.dueTick then
            canRun = true
            if SCHEDULE_MAX_PER_TICK > 0 then
                if ran >= SCHEDULE_MAX_PER_TICK then
                    canRun = false
                end
            end
        end

        if canRun then
            ran = ran + 1
            local succeeded, errorMessage = pcall(item.run)
            if not succeeded then
                log(string.format("SCHEDULE ERROR: %s", tostring(errorMessage)))
            end
        else
            remaining[#remaining + 1] = item
        end
    end
    scheduleQueue = remaining
end

local function StartPumpLoop()
    local now = nowSeconds()
    -- Avoid restart storms that kill LoopAsync before it can tick.
    if pumpRunning and (now - lastPumpRestartAt) < 5 then
        return
    end

    pumpRunning = true
    lastPumpTick = now
    lastPumpRestartAt = now

    pumpGeneration = pumpGeneration + 1
    local myGeneration = pumpGeneration

    LoopAsync(PUMP_INTERVAL_MS, function()
        if myGeneration ~= pumpGeneration then
            return true
        end

        -- Heartbeat even if the game-thread callback is delayed.
        lastPumpTick = nowSeconds()

        ExecuteInGameThread(function()
            local succeeded, errorMessage = pcall(pumpSchedule)
            if not succeeded then
                log(string.format("PUMP ERROR: %s", tostring(errorMessage)))
            end
        end)
        return false
    end)
end

EnsurePumpAlive = function()
    if not pumpRunning then
        StartPumpLoop()
        return
    end
    if nowSeconds() - lastPumpTick > PUMP_DEAD_SECONDS then
        log("schedule pump was dead -> restarted")
        -- Do NOT call pumpSchedule() here: that can run FX mid-combat with stale objects.
        StartPumpLoop()
    end
end

local assetWarned = {}

local function getModActorAsset(modActor, propertyName, fallbackPath)
    if modActor and modActor:IsValid() then
        local succeeded, value = pcall(function()
            return modActor[propertyName]
        end)
        if succeeded and value and value:IsValid() then

            local hasAsset, inner = pcall(function()
                return value.Template or value.Asset
            end)
            if hasAsset and inner and inner:IsValid() then
                return inner
            end
            return value
        end
    end

    if fallbackPath then
        local succeeded, found = pcall(function()
            return StaticFindObject(fallbackPath)
        end)
        if succeeded and found and found:IsValid() then
            return found
        end
    end

    if not assetWarned[propertyName] then
        assetWarned[propertyName] = true
        log(string.format(
            "ASSET MISSING: ModActor.%s が未設定です。UEでModActorに変数を追加し、"
            .. "既定値にアセットを設定してクックし直してください。", propertyName))
    end
    return nil
end

local function vecSub(a, b)
    return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function vecAdd(a, b)
    return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end

local function vecScale(a, s)
    return { X = a.X * s, Y = a.Y * s, Z = a.Z * s }
end

local function vecLength(a)
    return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
end

local function vecNormalize(a)
    local length = vecLength(a)
    if length < 0.0001 then
        return { X = 1.0, Y = 0.0, Z = 0.0 }
    end
    return vecScale(a, 1.0 / length)
end

local function vecCross(a, b)
    return {
        X = a.Y * b.Z - a.Z * b.Y,
        Y = a.Z * b.X - a.X * b.Z,
        Z = a.X * b.Y - a.Y * b.X,
    }
end

local function quatRotate(q, v)
    local tX = 2.0 * (q.Y * v.Z - q.Z * v.Y)
    local tY = 2.0 * (q.Z * v.X - q.X * v.Z)
    local tZ = 2.0 * (q.X * v.Y - q.Y * v.X)
    return {
        X = v.X + q.W * tX + (q.Y * tZ - q.Z * tY),
        Y = v.Y + q.W * tY + (q.Z * tX - q.X * tZ),
        Z = v.Z + q.W * tZ + (q.X * tY - q.Y * tX),
    }
end

local function quatUnrotate(q, v)
    return quatRotate({ X = -q.X, Y = -q.Y, Z = -q.Z, W = q.W }, v)
end

local function quatMul(a, b)
    return {
        X = a.W * b.X + a.X * b.W + a.Y * b.Z - a.Z * b.Y,
        Y = a.W * b.Y - a.X * b.Z + a.Y * b.W + a.Z * b.X,
        Z = a.W * b.Z + a.X * b.Y - a.Y * b.X + a.Z * b.W,
        W = a.W * b.W - a.X * b.X - a.Y * b.Y - a.Z * b.Z,
    }
end

local function randomInCone(direction, maxDegrees)
    local axis = vecNormalize(direction)

    local helper = { X = 0.0, Y = 0.0, Z = 1.0 }
    if math.abs(axis.Z) > 0.9 then
        helper = { X = 1.0, Y = 0.0, Z = 0.0 }
    end
    local right = vecNormalize(vecCross(axis, helper))
    local up = vecCross(axis, right)

    local theta = math.rad(maxDegrees) * math.sqrt(math.random())
    local phi = math.random() * math.pi * 2.0
    local sinTheta = math.sin(theta)

    local offset = vecAdd(
        vecScale(right, sinTheta * math.cos(phi)),
        vecScale(up, sinTheta * math.sin(phi)))
    return vecNormalize(vecAdd(vecScale(axis, math.cos(theta)), offset))
end

local kismetSystem = nil
local kismetMath = nil
local gameplayStatics = nil
local niagaraLibrary = nil
local kismetMaterial = nil

local niagaraAssetCache = {}

local function isNiagaraAsset(asset)
    local key = nil
    local okKey = pcall(function()
        key = asset:GetAddress()
    end)

    if okKey and key then
        local known = niagaraAssetCache[key]
        if known ~= nil then
            return known
        end
    end

    local result = false
    local ok, className = pcall(function()
        return asset:GetClass():GetFullName()
    end)
    if ok and className then
        result = string.find(tostring(className), "NiagaraSystem", 1, true) ~= nil
    end

    if okKey and key then
        niagaraAssetCache[key] = result
    end

    return result
end

local function getNiagaraLibrary()
    if not niagaraLibrary or not niagaraLibrary:IsValid() then
        niagaraLibrary = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
    end
    if niagaraLibrary and niagaraLibrary:IsValid() then
        return niagaraLibrary
    end
    log("FX: NiagaraFunctionLibrary が見つかりません")
    return nil
end

local FX_POOLING = 0
local FX_AUTO_DESTROY = (FX_POOLING == 0)

local function fxPoolArgs(pooling)
    local method = pooling
    if method == nil then
        method = FX_POOLING
    end
    return method, (method == 0)
end

local FX_ENABLED = true

local function spawnFxAtLocation(worldContext, asset, location, rotation, pooling, scale)
    if not FX_ENABLED then
        return
    end
    if not asset then
        return
    end

    local method, autoDestroy = fxPoolArgs(pooling)
    local s = scale
    if s == nil then
        s = 1.0
    end

    if isNiagaraAsset(asset) then
        local lib = getNiagaraLibrary()
        if not lib then
            return
        end

        lib:SpawnSystemAtLocation(
            worldContext, asset, location, rotation,
            { X = s, Y = s, Z = s },
            autoDestroy, true, method, true)
        return
    end

    gameplayStatics:SpawnEmitterAtLocation(
        worldContext, asset, location, rotation,
        { X = s, Y = s, Z = s }, autoDestroy, method, true)
end

local function spawnFxAttached(asset, mesh, boneName, location, rotation, locationType, pooling)
    if not FX_ENABLED then
        return
    end
    if not asset then
        return
    end

    local method, autoDestroy = fxPoolArgs(pooling)

    if isNiagaraAsset(asset) then
        local lib = getNiagaraLibrary()
        if not lib then
            return
        end

        lib:SpawnSystemAttached(
            asset, mesh, FName(boneName), location, rotation,
            locationType, autoDestroy, true, method, true)
        return
    end

    gameplayStatics:SpawnEmitterAttached(
        asset, mesh, FName(boneName), location, rotation,
        { X = 1.0, Y = 1.0, Z = 1.0 }, locationType,
        autoDestroy, method, true)
end

local SHADER_WARMUP = {
    -- 1.0.2: disabled (map-load FX warmup contributed to instability).
    Enabled       = false,
    DelayAfterLoad = 6.0,
    RetryInterval = 3.0,
    MaxAttempts   = 10,
    FxScale       = 0.05,
    DecalRadius   = 2.0,
    DecalLifeSpan = 2.0,
}

local shaderWarmupDone = false

local function getLibraries()
    if not kismetSystem then
        kismetSystem = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    end
    if not kismetMath then
        kismetMath = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    end
    if not gameplayStatics then
        gameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    end
    if not kismetMaterial then
        kismetMaterial = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    end
    return kismetSystem and kismetSystem:IsValid()
        and kismetMath and kismetMath:IsValid()
        and gameplayStatics and gameplayStatics:IsValid()
        and kismetMaterial and kismetMaterial:IsValid()
end

local function gameTimeSeconds(worldContext)
    if worldContext then
        if getLibraries() then
            local seconds = nil
            local ok = pcall(function()
                seconds = gameplayStatics:GetTimeSeconds(worldContext)
            end)
            if ok then
                if type(seconds) == "number" then
                    return seconds
                end
            end
        end
    end

    return pumpTicks * PUMP_INTERVAL
end

local function traceSurface(worldContext, startPoint, endPoint, ignoreActors)
    local resultLocation, resultNormal = nil, nil

    local succeeded, errorMessage = pcall(function()
        local hitResult = {}
        local didHit = kismetSystem:LineTraceSingle(
            worldContext,
            startPoint,
            endPoint,
            0,
            false,
            ignoreActors or {},
            0,
            hitResult,
            true,
            { R = 1.0, G = 0.0, B = 0.0, A = 1.0 },
            { R = 0.0, G = 1.0, B = 0.0, A = 1.0 },
            0.0)

        if didHit and hitResult then
            local point = hitResult.ImpactPoint or hitResult.Location
            local normal = hitResult.ImpactNormal or hitResult.Normal
            if point and normal then
                resultLocation = snapshotVector(point)
                resultNormal = snapshotVector(normal)
            end
        end
    end)

    if not succeeded then
        log(string.format("TRACE ERROR: %s", tostring(errorMessage)))
        return nil, nil
    end
    return resultLocation, resultNormal
end

local function spawnBloodDecal(worldContext, material, location, normal, diameter, direction)
    if not material then
        return
    end
    local succeeded, errorMessage = pcall(function()

        local axis = { X = -normal.X, Y = -normal.Y, Z = -normal.Z }

        local rotation = nil
        if direction ~= nil then
            local d = direction.X * normal.X
                + direction.Y * normal.Y
                + direction.Z * normal.Z
            local flow = {
                X = direction.X - normal.X * d,
                Y = direction.Y - normal.Y * d,
                Z = direction.Z - normal.Z * d,
            }
            local length = math.sqrt(flow.X * flow.X + flow.Y * flow.Y + flow.Z * flow.Z)
            if length > 0.01 then
                flow.X = flow.X / length
                flow.Y = flow.Y / length
                flow.Z = flow.Z / length
                rotation = kismetMath:MakeRotFromXZ(axis, flow)

                if SPATTER.DecalRoll ~= 0.0 then
                    rotation = kismetMath:ComposeRotators(
                        { Pitch = 0.0, Yaw = 0.0, Roll = SPATTER.DecalRoll },
                        rotation)
                end
            end
        end

        if rotation == nil then
            rotation = kismetMath:MakeRotFromX(axis)
        end

        local decal = gameplayStatics:SpawnDecalAtLocation(
            worldContext,
            material,
            { X = SPATTER.Depth, Y = diameter, Z = diameter },
            location,
            rotation,
            SPATTER.LifeSpan)

        if decal and decal:IsValid() then

            pcall(function()
                decal.FadeScreenSize = SPATTER.FadeScreenSize
            end)

            decal:SetFadeOut(
                SPATTER.LifeSpan - SPATTER.FadeDuration,
                SPATTER.FadeDuration,
                true)
        end
    end)

    if not succeeded then
        log(string.format("DECAL ERROR: %s", tostring(errorMessage)))
    end
end

local function placeOneSpatter(worldContext, origin, direction, ignoreActors, material)
    local range = SPATTER.RangeMin
        + math.random() * (SPATTER.RangeMax - SPATTER.RangeMin)
    local startPoint = vecAdd(origin, vecScale(direction, SPATTER.StartOffset))
    local endPoint = vecAdd(origin, vecScale(direction, range))

    local location, normal = traceSurface(worldContext, startPoint, endPoint, ignoreActors)

    if not location then

        local dropFrom = endPoint
        local dropTo = vecAdd(dropFrom, { X = 0.0, Y = 0.0, Z = -SPATTER.FallHeight })
        location, normal = traceSurface(worldContext, dropFrom, dropTo, ignoreActors)
    end

    if not location then
        return
    end

    local diameter = SPATTER.SizeMin
        + math.random() * (SPATTER.SizeMax - SPATTER.SizeMin)

    spawnBloodDecal(worldContext, material, location, normal, diameter, direction)
end

local function placeGroundSpatter(worldPath, location, normal, direction, material, diameter, depth, roll, sortOrder)
    local succeeded, errorMessage = pcall(function()

        local worldContext = nil
        if worldPath then
            if cachedBloodFXModActor and cachedModActorPath == worldPath then
                local okValid = pcall(function()
                    if cachedBloodFXModActor:IsValid() then
                        worldContext = cachedBloodFXModActor
                    end
                end)
                if not okValid then
                    worldContext = nil
                end
            end

            if not worldContext then
                local ok, found = pcall(function()
                    return StaticFindObject(worldPath)
                end)
                if ok and found then
                    worldContext = found
                end
            end
        end
        if not worldContext then
            return
        end
        if not getLibraries() then
            return
        end

        local axis = { X = -normal.X, Y = -normal.Y, Z = -normal.Z }

        local rotation = nil
        local d = direction.X * normal.X + direction.Y * normal.Y + direction.Z * normal.Z
        local flow = {
            X = direction.X - normal.X * d,
            Y = direction.Y - normal.Y * d,
            Z = direction.Z - normal.Z * d,
        }
        local length = math.sqrt(flow.X * flow.X + flow.Y * flow.Y + flow.Z * flow.Z)
        if length > 0.01 then
            flow.X = flow.X / length
            flow.Y = flow.Y / length
            flow.Z = flow.Z / length
            rotation = kismetMath:MakeRotFromXZ(axis, flow)
        else
            rotation = kismetMath:MakeRotFromX(axis)
        end

        local totalRoll = SPATTER.DecalRoll + (roll or 0.0)
        if totalRoll ~= 0.0 then
            rotation = kismetMath:ComposeRotators(
                { Pitch = 0.0, Yaw = 0.0, Roll = totalRoll },
                rotation)
        end

        local decal = gameplayStatics:SpawnDecalAtLocation(
            worldContext,
            material,
            { X = depth or SPATTER.GroundDepth, Y = diameter, Z = diameter },
            location,
            rotation,
            SPATTER.LifeSpan)

        if decal and decal:IsValid() then
            pcall(function()
                decal.FadeScreenSize = SPATTER.FadeScreenSize
            end)
            decal:SetFadeOut(
                SPATTER.LifeSpan - SPATTER.FadeDuration,
                SPATTER.FadeDuration,
                true)
        end
    end)

    if not succeeded then
        log(string.format("SPATTER ERROR: %s", tostring(errorMessage)))
    end
end

local function placeOneSpatterByPath(defenderPath, attackerPath, worldPath, origin, direction, material)
    local succeeded, errorMessage = pcall(function()
        local defender = nil
        if defenderPath then
            local ok, found = pcall(function()
                return StaticFindObject(defenderPath)
            end)
            if ok and found then
                defender = found
            end
        end

        local worldContext = defender
        if not worldContext and worldPath then
            local ok, found = pcall(function()
                return StaticFindObject(worldPath)
            end)
            if ok and found then
                worldContext = found
            end
        end
        if not worldContext then
            return
        end

        local ignoreActors = {}
        if defender then
            ignoreActors[#ignoreActors + 1] = defender
        end
        if attackerPath then
            local ok, attacker = pcall(function()
                return StaticFindObject(attackerPath)
            end)
            if ok and attacker then
                ignoreActors[#ignoreActors + 1] = attacker
            end
        end

        placeOneSpatter(worldContext, origin, direction, ignoreActors, material)
    end)

    if not succeeded then
        log(string.format("SPATTER ERROR: %s", tostring(errorMessage)))
    end
end

local function playImpactBloodEffect(defender, particleSystem, location, direction)
    if not particleSystem then
        return
    end

    local succeeded, errorMessage = pcall(function()
        local rotation = kismetMath:MakeRotFromX(direction)

        if SPATTER.AttachToBone then
            local mesh = defender.Mesh

            local boneName = SPATTER.FixedImpactBone
            if not boneName then
                boneName = findNearestBoneName(mesh, location)
            end

            if mesh and mesh:IsValid() and boneName then

                spawnFxAttached(particleSystem, mesh, boneName, location, rotation,
                    1, SPATTER.FxPooling)
                return
            end
        end

        spawnFxAtLocation(defender, particleSystem, location, rotation,
            SPATTER.FxPooling)
    end)

    if not succeeded then
        log(string.format("IMPACT FX ERROR: %s", tostring(errorMessage)))
    end
end

local cachedDecalMaterials = nil
local cachedDecalMaterialSource = nil

local cachedDecalRolls = nil
local cachedDecalMaterialOwner = nil

local cachedBloodPoolClass = nil

local spatterTimeByActor = {}

local impactFxTimeByActor = {}
local spatterActorCount = 0
local globalSpatterWindowStart = 0.0
local globalSpatterWindowCount = 0

local function resolveDecalRoll(material)
    local roll = 0.0

    pcall(function()
        local name = material:GetFName():ToString()
        local found = SPATTER.DecalRollByName[name]
        if found ~= nil then
            roll = found
        end
    end)

    return roll
end

local function collectDecalMaterials(modActor)
    if not modActor or not modActor:IsValid() then
        return nil
    end

    local candidates = { "BloodDecalMaterials", "BloodDecalMaterial" }

    for _, propertyName in ipairs(candidates) do
        local value = nil
        pcall(function()
            value = modActor[propertyName]
        end)

        if value ~= nil then

            local list = {}
            pcall(function()
                value:ForEach(function(_, element)
                    local item = element
                    pcall(function()
                        item = element:get()
                    end)
                    local ok = false
                    pcall(function()
                        ok = item ~= nil and item:IsValid()
                    end)
                    if ok then
                        list[#list + 1] = item
                    end
                end)
            end)
            if #list > 0 then

                local rolls = {}
                for index, item in ipairs(list) do
                    rolls[index] = resolveDecalRoll(item)
                end
                return list, propertyName, rolls
            end

            local single = false
            pcall(function()
                single = value:IsValid()
            end)
            if single then
                return { value }, propertyName, { resolveDecalRoll(value) }
            end
        end
    end

    return nil
end

local function getRefPoseComponent(mesh, boneName)

    local assetKey = 0
    pcall(function()
        local asset = mesh.SkeletalMesh
        if asset and asset:IsValid() then
            assetKey = asset:GetAddress()
        end
    end)

    local perMesh = refPoseComponentCache[assetKey]
    if perMesh == nil then
        if refPoseMeshCount > 32 then
            refPoseComponentCache = {}
            refPoseMeshCount = 0
        end
        perMesh = {}
        refPoseComponentCache[assetKey] = perMesh
        refPoseMeshCount = refPoseMeshCount + 1
    end

    local cached = perMesh[boneName]
    if cached then
        return cached
    end

    local chain = {}
    local current = boneName
    for _ = 1, 64 do
        table.insert(chain, 1, current)
        local parent = mesh:GetParentBone(boneFName(current)):ToString()
        if parent == "None" or parent == "" then
            break
        end
        current = parent
    end

    local position = { X = 0.0, Y = 0.0, Z = 0.0 }
    local rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }
    for _, name in ipairs(chain) do
        local index = mesh:GetBoneIndex(boneFName(name))
        if index == nil or index < 0 then
            return nil
        end
        local localTransform = mesh:GetRefPoseTransform(index)
        local localPos = localTransform.Translation
        local localRot = localTransform.Rotation

        local rotated = quatRotate(rotation, localPos)
        position = {
            X = position.X + rotated.X,
            Y = position.Y + rotated.Y,
            Z = position.Z + rotated.Z,
        }
        rotation = quatMul(rotation,
            { X = localRot.X, Y = localRot.Y, Z = localRot.Z, W = localRot.W })
    end

    cached = { position = position, rotation = rotation }
    perMesh[boneName] = cached
    return cached
end

local function applyBodyBlood(defender, modActor, hitLocation)
    if not BODY_BLOOD.Enabled then
        return
    end

    local succeeded, errorMessage = pcall(function()
        local mesh = defender.Mesh
        if not mesh or not mesh:IsValid() then
            return
        end

        local overlaySource = getModActorAsset(modActor, "BloodOverlayMaterial", nil)
        if not overlaySource or not overlaySource:IsValid() then
            if not assetWarned["BloodOverlayMaterial"] then
                assetWarned["BloodOverlayMaterial"] = true
                log("ASSET MISSING: ModActor.BloodOverlayMaterial が未設定です")
            end
            return
        end

        local mid = nil
        local existing = mesh:GetOverlayMaterial()
        if existing and existing:IsValid() then
            local okParent = pcall(function()
                local parent = existing.Parent
                if parent and parent:IsValid()
                    and parent:GetAddress() == overlaySource:GetAddress() then
                    mid = existing
                end
            end)
            if not okParent then
                return
            end
            if not mid then
                return
            end
        else
            if not getLibraries() then
                return
            end

            mid = kismetMaterial:CreateDynamicMaterialInstance(
                defender, overlaySource, boneFName("None"), 0)
            if not mid or not mid:IsValid() then
                return
            end
            mid:SetScalarParameterValue(boneFName("HitRadius"), BODY_BLOOD.Radius)
            mid:SetScalarParameterValue(boneFName("Alpha"), BODY_BLOOD.Alpha)
            mid:SetScalarParameterValue(boneFName("HitHardness"), BODY_BLOOD.Hardness)
            mid:SetScalarParameterValue(boneFName("TexCutoff"), BODY_BLOOD.TexCutoff)
            mid:SetScalarParameterValue(boneFName("TexSoftness"), BODY_BLOOD.TexSoftness)
            mid:SetVectorParameterValue(boneFName("BloodColor"), {
                R = BODY_BLOOD.Color.R, G = BODY_BLOOD.Color.G,
                B = BODY_BLOOD.Color.B, A = 1.0,
            })
            mesh:SetOverlayMaterial(mid)

            local partsOk, partsError = pcall(function()
                if not cachedSkelMeshCompClass
                    or not cachedSkelMeshCompClass:IsValid() then
                    cachedSkelMeshCompClass = StaticFindObject(
                        "/Script/Engine.SkeletalMeshComponent")
                end
                if not cachedSkelMeshCompClass
                    or not cachedSkelMeshCompClass:IsValid() then
                    error("SkeletalMeshComponent クラスが見つかりません")
                end
                local parts = defender:K2_GetComponentsByClass(
                    cachedSkelMeshCompClass)
                if not parts then
                    error("K2_GetComponentsByClass が nil を返しました")
                end
                local total, applied = 0, 0
                local names = {}

                local count = #parts
                for i = 1, count do
                    local part = parts[i]

                    if part ~= nil then
                        local okGet, unwrapped = pcall(function()
                            return part:get()
                        end)
                        if okGet and unwrapped ~= nil then
                            part = unwrapped
                        end
                    end
                    if part and part:IsValid()
                        and part:GetAddress() ~= mesh:GetAddress() then
                        total = total + 1
                        if not assetWarned["BodyBloodParts"] then
                            table.insert(names, part:GetFName():ToString())
                        end
                        local occupied = part:GetOverlayMaterial()
                        if not occupied or not occupied:IsValid() then
                            part:SetOverlayMaterial(mid)
                            applied = applied + 1
                        end
                    end
                end

                if not assetWarned["BodyBloodParts"] then
                    assetWarned["BodyBloodParts"] = true
                    log(string.format(
                        "BODY BLOOD: 部品 %d 件中 %d 件へ配布 [%s]",
                        total, applied, table.concat(names, ", ")))
                end
            end)
            if not partsOk then
                if not assetWarned["BodyBloodPartsError"] then
                    assetWarned["BodyBloodPartsError"] = true
                    log(string.format("BODY BLOOD PARTS ERROR: %s",
                        tostring(partsError)))
                end
            end
        end

        if BODY_BLOOD.DebugRefDump then
            if not assetWarned["BodyBloodRefDump"] then
                assetWarned["BodyBloodRefDump"] = true
                for _, dumpBone in ipairs({ "pelvis", "spine_02", "head",
                        "thigh_l", "calf_l", "foot_l", "upperarm_l", "hand_l" }) do
                    local ref = getRefPoseComponent(mesh, dumpBone)
                    if ref then
                        log(string.format(
                            "REF DUMP %-12s pos=(%.1f, %.1f, %.1f)",
                            dumpBone, ref.position.X, ref.position.Y,
                            ref.position.Z))
                    else
                        log(string.format("REF DUMP %-12s 取得失敗", dumpBone))
                    end
                end
            end
        end

        if BODY_BLOOD.DebugProbe then
            mid:SetVectorParameterValue(boneFName("Hit0"),
                { R = 0.0, G = 0.0, B = 120.0, A = 1.0 })
            mid:SetVectorParameterValue(boneFName("Hit1"),
                { R = 0.0, G = 0.0, B = 30.0, A = 1.0 })
            if not assetWarned["BodyBloodProbe"] then
                assetWarned["BodyBloodProbe"] = true
                log("BODY BLOOD PROBE: Hit0=(0,0,120) Hit1=(0,0,30) を書き込みました")
            end
            return
        end

        local boneName = nil
        local okClosest = pcall(function()
            local found = mesh:FindClosestBone(hitLocation, {}, 0.0, false)
            if found then
                local text = found:ToString()
                if text ~= "" and text ~= "None" then
                    boneName = text
                end
            end
        end)
        if not okClosest or not boneName then
            boneName = findNearestBoneName(mesh, hitLocation)
        end
        if not boneName then
            return
        end

        if not BODY_BLOOD_BONE_SET[boneName] then
            local current = boneName
            for _ = 1, 64 do
                local parent = mesh:GetParentBone(boneFName(current)):ToString()
                if parent == "None" or parent == "" then
                    break
                end
                if BODY_BLOOD_BONE_SET[parent] then
                    boneName = parent
                    break
                end
                current = parent
            end
            if not BODY_BLOOD_BONE_SET[boneName] then
                boneName = findNearestBoneName(mesh, hitLocation)
                if not boneName then
                    return
                end
            end
        end

        if BODY_BLOOD.SkipBones[boneName] then
            return
        end

        local socket = mesh:GetSocketTransform(boneFName(boneName), 0)
        local translation = socket.Translation
        local rotationQ = socket.Rotation
        local offset = quatUnrotate(rotationQ, {
            X = hitLocation.X - translation.X,
            Y = hitLocation.Y - translation.Y,
            Z = hitLocation.Z - translation.Z,
        })

        local rawDistance = math.sqrt(offset.X * offset.X
            + offset.Y * offset.Y + offset.Z * offset.Z)
        if BODY_BLOOD.RejectDistance > 0
            and rawDistance > BODY_BLOOD.RejectDistance then
            if BODY_BLOOD.DebugLog then
                log(string.format(
                    "BODY BLOOD SKIP bone=%s dist=%.1f (異常値)",
                    boneName, rawDistance))
            end
            return
        end

        local ref = getRefPoseComponent(mesh, boneName)
        if not ref then
            return
        end
        local rotated = quatRotate(ref.rotation, offset)
        local preSkinned = {
            X = ref.position.X + rotated.X,
            Y = ref.position.Y + rotated.Y,
            Z = ref.position.Z + rotated.Z,
        }

        local key = defender:GetAddress()
        local index = bodyBloodNextIndex[key]
        if index == nil then
            if bodyBloodActorCount > 64 then
                bodyBloodNextIndex = {}
                bodyBloodActorCount = 0
            end
            index = 0
            bodyBloodActorCount = bodyBloodActorCount + 1
        end
        bodyBloodNextIndex[key] = (index + 1) % BODY_BLOOD.MaxHits

        mid:SetVectorParameterValue(boneFName("Hit" .. index), {
            R = preSkinned.X, G = preSkinned.Y, B = preSkinned.Z, A = 1.0,
        })

        if BODY_BLOOD.DebugLog then
            log(string.format(
                "BODY BLOOD #%d bone=%s dist=%.1f pre=(%.1f, %.1f, %.1f)"
                .. " hit=(%.0f, %.0f, %.0f) boneW=(%.0f, %.0f, %.0f)"
                .. " off=(%.1f, %.1f, %.1f)",
                index, boneName, rawDistance,
                preSkinned.X, preSkinned.Y, preSkinned.Z,
                hitLocation.X, hitLocation.Y, hitLocation.Z,
                translation.X, translation.Y, translation.Z,
                offset.X, offset.Y, offset.Z))
        end
    end)

    if not succeeded then
        if not assetWarned["BodyBloodError"] then
            assetWarned["BodyBloodError"] = true
            log(string.format("BODY BLOOD ERROR: %s", tostring(errorMessage)))
        end
    end
end

local function runShaderWarmup()
    if shaderWarmupDone then
        return
    end
    if not FX_ENABLED then
        return
    end

    local succeeded, errorMessage = pcall(function()

        local player = FindFirstOf("PalPlayerCharacter")
        if not player or not player:IsValid() then
            return
        end

        local modActor = findBloodFXModActor(player)
        if not modActor then
            return
        end

        if not getLibraries() then
            return
        end

        shaderWarmupDone = true

        local origin = player:K2_GetActorLocation()
        local feet = { X = origin.X, Y = origin.Y, Z = origin.Z - 85.0 }
        local rotation = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }

        for _, name in ipairs({ "HitBloodFX", "HeadGoreFX" }) do
            local asset = getModActorAsset(modActor, name, nil)
            if asset and asset:IsValid() then
                spawnFxAtLocation(player, asset, feet, rotation,
                    0, SHADER_WARMUP.FxScale)
            end
        end

        local materials = collectDecalMaterials(modActor)
        local count = 0
        if materials then
            local downward = { Pitch = -90.0, Yaw = 0.0, Roll = 0.0 }
            for _, material in ipairs(materials) do
                local decal = gameplayStatics:SpawnDecalAtLocation(
                    player, material,
                    { X = SHADER_WARMUP.DecalRadius,
                      Y = SHADER_WARMUP.DecalRadius,
                      Z = SHADER_WARMUP.DecalRadius },
                    feet, downward, SHADER_WARMUP.DecalLifeSpan)
                if decal and decal:IsValid() then
                    count = count + 1
                end
            end
        end

        local overlayWarmed = false
        local overlaySource = nil
        if BODY_BLOOD.Enabled then
            overlaySource = getModActorAsset(modActor, "BloodOverlayMaterial", nil)
        end
        if overlaySource and overlaySource:IsValid() then
            local mesh = player.Mesh
            if mesh and mesh:IsValid() then
                local existing = mesh:GetOverlayMaterial()
                if not existing or not existing:IsValid() then
                    local mid = kismetMaterial:CreateDynamicMaterialInstance(
                        player, overlaySource, boneFName("None"), 0)
                    if mid and mid:IsValid() then
                        mesh:SetOverlayMaterial(mid)
                        overlayWarmed = true
                    end
                end
            end
        end

        if not cachedBloodPoolClass or not cachedBloodPoolClass:IsValid() then
            local poolClass = StaticFindObject(
                "/Game/Mods/BloodFX/BP_BloodPool.BP_BloodPool_C")
            if poolClass and poolClass:IsValid() then
                cachedBloodPoolClass = poolClass
            end
        end

        log(string.format(
            "WARMUP: シェーダを温めました (デカール%d種 + FX2種 + 体表の血=%s)",
            count, tostring(overlayWarmed)))
    end)

    if not succeeded then
        log(string.format("WARMUP ERROR: %s", tostring(errorMessage)))
    end
end

local function scheduleWarmupAttempt(attempt)
    local delay = SHADER_WARMUP.RetryInterval
    if attempt == 1 then
        delay = SHADER_WARMUP.DelayAfterLoad
    end
    Schedule(delay, function()
        runShaderWarmup()
        if not shaderWarmupDone then
            if attempt < SHADER_WARMUP.MaxAttempts then
                scheduleWarmupAttempt(attempt + 1)
            else
                log("WARMUP: 再試行の上限に達しました。最初の被弾時に温めます")
            end
        end
    end)
end

local function triggerBloodSpatter(defender, attacker, hitLocation, isHeadshotKill, isPal, isDead)
    if not SPATTER.Enabled then
        return
    end

    -- Pals: death-time spray/pool only (hit spam was crashing UE4SS).
    if isPal and not SPATTER.PalHitSpatter and not isDead then
        return
    end

    EnsurePumpAlive()

    local okValid, isValid = pcall(function()
        return defender and defender:IsValid()
    end)
    if not okValid or not isValid then
        return
    end

    local throttled = false
    local fxThrottled = false

    local key = nil
    local okKey = pcall(function()
        key = defender:GetAddress()
    end)
    if okKey and key then

        local now = gameTimeSeconds(defender)

        -- Global combat spam cap (native AVs rise when every pal hit spawns FX).
        if now - globalSpatterWindowStart >= 1.0 then
            globalSpatterWindowStart = now
            globalSpatterWindowCount = 0
        end
        local maxPerSec = SPATTER.GlobalMaxPerSecond or 8
        if globalSpatterWindowCount >= maxPerSec then
            return
        end
        globalSpatterWindowCount = globalSpatterWindowCount + 1

        local minInterval = SPATTER.MinIntervalPerActor or 1.0
        if isPal and SPATTER.MinIntervalPerPal then
            minInterval = SPATTER.MinIntervalPerPal
        end

        local last = spatterTimeByActor[key]
        if last ~= nil then
            if now >= last then
                if (now - last) < minInterval then
                    throttled = true
                end
            end
        end

        local lastFx = impactFxTimeByActor[key]
        if lastFx ~= nil then
            if now >= lastFx then
                if (now - lastFx) < SPATTER.ImpactFxInterval then
                    fxThrottled = true
                end
            end
        end

        if isHeadshotKill and SPATTER.HeadshotBypassThrottle then
            throttled = false
        end

        if spatterActorCount > 32 then
            spatterTimeByActor = {}
            impactFxTimeByActor = {}
            spatterActorCount = 0
        end

        if not throttled then
            spatterTimeByActor[key] = now
            spatterActorCount = spatterActorCount + 1
        end
        if not fxThrottled then
            impactFxTimeByActor[key] = now
        end
    end

    if throttled and (fxThrottled or not SPATTER.ImpactFxEnabled) then
        return
    end

    local hit = snapshotVector(hitLocation)
    local attackerSnapshot = nil
    local ok = pcall(function()
        if attacker and attacker:IsValid() then
            attackerSnapshot = snapshotVector(attacker:K2_GetActorLocation())
        end
    end)
    if not ok or not attackerSnapshot then
        return
    end

    local toAttacker = vecNormalize(vecSub(attackerSnapshot, hit))
    local defenderRef = defender
    local attackerRef = attacker

    runOnGameThread(function()
        if not stillValid(defenderRef) then
            return
        end
        local defender = defenderRef
        local attacker = stillValid(attackerRef) and attackerRef or nil
        local defenderPath = objectSoftPath(defender)
        local attackerPath = attacker and objectSoftPath(attacker) or nil

        if not getLibraries() then
            log("SPATTER: Kismet/GameplayStatics が見つかりません")
            return
        end

        local modActor = findBloodFXModActor(defender)

        runShaderWarmup()

        local materials, foundName = cachedDecalMaterials, cachedDecalMaterialSource
        local rolls = cachedDecalRolls
        if materials == nil or cachedDecalMaterialOwner ~= modActor then
            materials, foundName, rolls = collectDecalMaterials(modActor)
            cachedDecalMaterials = materials
            cachedDecalMaterialSource = foundName
            cachedDecalRolls = rolls
            cachedDecalMaterialOwner = modActor
        end
        if not assetWarned["BloodDecalMaterialList"] then
            assetWarned["BloodDecalMaterialList"] = true
            if materials then
                log(string.format("SPATTER: デカールのマテリアル %d 件を取得 (%s)",
                    #materials, tostring(foundName)))
            else
                log("ASSET MISSING: ModActor.BloodDecalMaterial が未設定です。"
                    .. "UEでModActorに変数を追加し、既定値にアセットを設定してクックし直してください。")
            end
        end

        if SPATTER.ImpactFxEnabled and not fxThrottled then
            local particleSystem = getModActorAsset(modActor, "HitBloodFX",
                "/Game/Mods/BloodFX/Realistic_Starter_VFX_Pack_Vol2/Particles/Blood/"
                .. "P_Blood_Splat_Cone.P_Blood_Splat_Cone")

            local fxDirection = toAttacker
            if not SPATTER.ImpactFxTowardAttacker then
                fxDirection = { X = -toAttacker.X, Y = -toAttacker.Y, Z = -toAttacker.Z }
            end
            playImpactBloodEffect(defender, particleSystem, hit, fxDirection)
        end

        applyBodyBlood(defender, modActor, hit)

        if throttled then
            return
        end

        if not materials then
            return
        end

        local modActorPath = cachedModActorPath

        local awayFromAttacker = {
            X = -toAttacker.X, Y = -toAttacker.Y, Z = -toAttacker.Z,
        }

        local groundLocation, groundNormal = nil, nil
        if SPATTER.GroundOnly then

            if SPATTER.GroundFromCapsule then
                pcall(function()
                    local capsule = defender.CapsuleComponent
                    if capsule and capsule:IsValid() then
                        local center = defender:K2_GetActorLocation()
                        local halfHeight = capsule:GetScaledCapsuleHalfHeight()
                        if halfHeight and halfHeight > 0.0 then
                            groundLocation = {
                                X = hit.X, Y = hit.Y,
                                Z = center.Z - halfHeight,
                            }
                            groundNormal = { X = 0.0, Y = 0.0, Z = 1.0 }
                        end
                    end
                end)
            end

            if not groundLocation then
                local ignoreActors = {}
                if defender and defender:IsValid() then
                    ignoreActors[#ignoreActors + 1] = defender
                end
                if attacker and attacker:IsValid() then
                    ignoreActors[#ignoreActors + 1] = attacker
                end

                local from = { X = hit.X, Y = hit.Y, Z = hit.Z + 50.0 }
                local to = { X = hit.X, Y = hit.Y, Z = hit.Z - 500.0 }
                groundLocation, groundNormal = traceSurface(defender, from, to, ignoreActors)
            end

            if not groundLocation then
                return
            end
        end

        local wallAllowed = true
        if SPATTER.WallOnlyOnHeadshot and not isHeadshotKill then
            wallAllowed = false
        end
        if wallAllowed and SPATTER.GroundOnly and SPATTER.WallDecals and materials then
            local flat = { X = awayFromAttacker.X, Y = awayFromAttacker.Y, Z = 0.0 }
            local flatLength = math.sqrt(flat.X * flat.X + flat.Y * flat.Y)
            if flatLength > 0.01 then
                flat.X = flat.X / flatLength
                flat.Y = flat.Y / flatLength

                if SPATTER.WallViaBP then
                    local wallScale = 1.0
                    if isHeadshotKill then
                        wallScale = SPATTER.HeadshotWallScale
                    end
                    local okWall, wallError = pcall(function()
                        modActor:SpawnWallSplatter(
                            { X = hit.X, Y = hit.Y, Z = hit.Z },
                            { X = flat.X, Y = flat.Y, Z = 0.0 },
                            wallScale)
                    end)

                    if not okWall then
                        if not assetWarned["SpawnWallSplatter"] then
                            assetWarned["SpawnWallSplatter"] = true
                            log(string.format("WALL BP ERROR: %s",
                                tostring(wallError)))
                        end
                    end
                else

                local ignoreWall = {}
                if defender and defender:IsValid() then
                    ignoreWall[#ignoreWall + 1] = defender
                end
                if attacker and attacker:IsValid() then
                    ignoreWall[#ignoreWall + 1] = attacker
                end

                local wallTo = {
                    X = hit.X + flat.X * SPATTER.WallRange,
                    Y = hit.Y + flat.Y * SPATTER.WallRange,
                    Z = hit.Z,
                }
                local wallLocation, wallNormal =
                    traceSurface(defender, hit, wallTo, ignoreWall)

                if wallLocation and wallNormal then
                    for wallIndex = 1, SPATTER.WallCount do
                        local pick = math.random(1, #materials)
                        local material = materials[pick]
                        local roll = SPATTER.WallDecalRoll
                        if rolls then
                            roll = roll + (rolls[pick] or 0.0)
                        end
                        local diameter = SPATTER.SizeMin
                            + math.random() * (SPATTER.SizeMax - SPATTER.SizeMin)

                        if isHeadshotKill then
                            diameter = diameter * SPATTER.HeadshotWallScale
                        end

                        local spread = SPATTER.WallSpread
                        local spot = {
                            X = wallLocation.X + (math.random() - 0.5) * spread,
                            Y = wallLocation.Y + (math.random() - 0.5) * spread,
                            Z = wallLocation.Z + (math.random() - 0.5) * spread,
                        }
                        local downward = { X = 0.0, Y = 0.0, Z = -1.0 }

                        local slot = SPATTER.Count + wallIndex - 1
                        Schedule(slot * SPATTER.SpreadInterval, function()
                            placeGroundSpatter(modActorPath, spot, wallNormal,
                                downward, material, diameter, SPATTER.WallDepth, roll)
                        end)
                    end
                end

                end
            end
        end

        for index = 1, SPATTER.Count do
            local axis = toAttacker
            if math.random() < SPATTER.ForwardRatio then
                axis = awayFromAttacker
            end
            local direction = randomInCone(axis, SPATTER.ConeDegrees)
            local pick = math.random(1, #materials)
            local material = materials[pick]
            local roll = 0.0
            if rolls then
                roll = rolls[pick] or 0.0
            end
            local diameter = SPATTER.SizeMin
                + math.random() * (SPATTER.SizeMax - SPATTER.SizeMin)

            local run = nil
            if SPATTER.GroundOnly then

                local range = SPATTER.RangeMin
                    + math.random() * (SPATTER.RangeMax - SPATTER.RangeMin)
                local flat = { X = direction.X, Y = direction.Y, Z = 0.0 }
                local flatLength = math.sqrt(flat.X * flat.X + flat.Y * flat.Y)
                if flatLength > 0.01 then
                    flat.X = flat.X / flatLength
                    flat.Y = flat.Y / flatLength
                end
                local spot = {
                    X = groundLocation.X + flat.X * range,
                    Y = groundLocation.Y + flat.Y * range,
                    Z = groundLocation.Z,
                }

                run = function()
                    local currentMaterials = cachedDecalMaterials
                    if not currentMaterials then
                        return
                    end
                    local freshMaterial = currentMaterials[pick]
                    if not freshMaterial then
                        return
                    end
                    placeGroundSpatter(modActorPath, spot, groundNormal,
                        direction, freshMaterial, diameter, nil, roll)
                end
            else
                run = function()
                    placeOneSpatterByPath(defenderPath, attackerPath, modActorPath,
                        hit, direction, material)
                end
            end

            if SPATTER.SpreadInterval > 0.0 then
                Schedule((index - 1) * SPATTER.SpreadInterval, run)
            else
                run()
            end
        end
    end)
end

local decalsDeniedOn = {}

local function denyDecalsOnMesh(defender)
    local ok, errorMessage = pcall(function()
        if not defender or not defender:IsValid() then
            return
        end

        local key = defender:GetAddress()
        if decalsDeniedOn[key] then
            return
        end

        local mesh = defender.Mesh
        if not mesh or not mesh:IsValid() then
            return
        end

        mesh:SetReceivesDecals(false)
        decalsDeniedOn[key] = true
    end)

    if not ok then
        log(string.format("DENY DECALS ERROR: %s", tostring(errorMessage)))
    end
end

local BLOOD_POOL = {

    Enabled     = true,

    Delay       = 0.25,
    HeightAbove = 40.0,
    Bone        = "pelvis",

    MarkDecapitation = false,

    -- 1.0.2: attaching pools to ragdolls/corpses can AV in UE4SS.
    AttachToCorpse = false,

    RandomMaterial = false,
    Materials = {
        "/Game/BloodPack/_Commons/Materials/Decals/Puddles/MI_BloodPuddle_01.MI_BloodPuddle_01",
        "/Game/BloodPack/_Commons/Materials/Decals/Puddles/MI_BloodPuddle_02.MI_BloodPuddle_02",
        "/Game/BloodPack/_Commons/Materials/Decals/Puddles/MI_BloodPuddle_03.MI_BloodPuddle_03",
        "/Game/BloodPack/_Commons/Materials/Decals/Puddles/MI_BloodPuddle_04.MI_BloodPuddle_04",
    },

    SizeScale   = 1.0,
}

local function spawnBloodPool(defender, isHeadshotKill)
    if not BLOOD_POOL.Enabled then
        return
    end

    if not stillValid(defender) then
        return
    end
    local defenderRef = defender

    local function doSpawn()
        local succeeded, errorMessage = pcall(function()
            if not stillValid(defenderRef) then
                return
            end
            local defender = defenderRef

            local firstTime = not assetWarned["BloodPoolClass"]

            local poolClass = cachedBloodPoolClass
            if not poolClass or not poolClass:IsValid() then
                local ok, found = pcall(function()
                    return StaticFindObject("/Game/Mods/BloodFX/BP_BloodPool.BP_BloodPool_C")
                end)
                if ok and found and found:IsValid() then
                    poolClass = found
                    cachedBloodPoolClass = found
                else
                    poolClass = nil
                end
            end

            if firstTime then
                assetWarned["BloodPoolClass"] = true
                if poolClass then
                    log("BLOOD POOL: クラス取得 OK")
                else
                    log("ASSET MISSING: BP_BloodPool_C が見つかりません。"
                        .. "pakに含まれているか、ModActor にクラス参照変数があるか確認してください。")
                end
            end

            if not poolClass then
                return
            end

            local location = nil
            local mesh = defender.Mesh
            if mesh and mesh:IsValid() then
                location = getSocketLocationOrNil(mesh, BLOOD_POOL.Bone)
            end
            if not location then
                location = getActorLocationSnapshot(defender)
            end

            location.Z = location.Z + BLOOD_POOL.HeightAbove

            local world = defender:GetWorld()
            if not world or not world:IsValid() then
                log("BLOOD POOL: World が取得できません")
                return
            end

            local actor = world:SpawnActor(poolClass, location, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
            if not actor or not actor:IsValid() then
                log("BLOOD POOL: SpawnActor に失敗しました")
                return
            end

            if isHeadshotKill and BLOOD_POOL.MarkDecapitation then
                local okFlag, flagError = pcall(function()
                    actor.IsDecapitation = true
                end)
                if not okFlag then
                    log(string.format(
                        "BLOOD POOL: IsDecapitation を書けません %s",
                        tostring(flagError)))
                end
            end

            if BLOOD_POOL.AttachToCorpse then
                local okAttach, attachError = pcall(function()
                    local corpseMesh = defender.Mesh
                    if corpseMesh and corpseMesh:IsValid()
                        and meshHasSocket(corpseMesh, BLOOD_POOL.Bone) then
                        actor:K2_AttachToComponent(
                            corpseMesh, FName(BLOOD_POOL.Bone), 2, 1, 1, false)
                    end
                end)
                if not okAttach then
                    log(string.format("BLOOD POOL: アタッチに失敗 %s", tostring(attachError)))
                end
            end

            if BLOOD_POOL.RandomMaterial then
                local okMaterial, materialError = pcall(function()
                    local decal = actor.BloodDecal
                    if not decal or not decal:IsValid() then
                        log("BLOOD POOL: BloodDecal が取得できません")
                        return
                    end

                    local path = BLOOD_POOL.Materials[
                        math.random(1, #BLOOD_POOL.Materials)]
                    local material = StaticFindObject(path)
                    if not material or not material:IsValid() then

                        log(string.format(
                            "BLOOD POOL: マテリアルが見つかりません %s", path))
                        return
                    end

                    decal:SetDecalMaterial(material)

                    local mid = decal:CreateDynamicMaterialInstance()
                    if mid and mid:IsValid() then
                        actor.MID = mid
                    end
                end)
                if not okMaterial then
                    log(string.format("BLOOD POOL: マテリアル差し替えに失敗 %s",
                        tostring(materialError)))
                end
            end

            if BLOOD_POOL.SizeScale ~= 1.0 then
                local okScale, scaleError = pcall(function()
                    local current = actor:GetActorScale3D()
                    actor:SetActorScale3D({
                        X = current.X,
                        Y = current.Y * BLOOD_POOL.SizeScale,
                        Z = current.Z * BLOOD_POOL.SizeScale,
                    })
                end)
                if not okScale then
                    log(string.format("BLOOD POOL: スケール調整に失敗 %s", tostring(scaleError)))
                end
            end
        end)

        if not succeeded then
            log(string.format("BLOOD POOL ERROR: %s", tostring(errorMessage)))
        end
    end

    -- Always leave the native damage hook first (Schedule already runs on game thread).
    EnsurePumpAlive()
    local delay = BLOOD_POOL.Delay
    if delay == nil or delay < 0.05 then
        delay = 0.05
    end
    Schedule(delay, doSpawn)
end

local NECK_DECAL = {

    Enabled  = false,

    MaterialIndex = 1,

    Bone       = "neck_01",

    Delay      = 0.0,

    Diameter   = 90.0,

    Depth      = 60.0,

    TailOffset = 0.0,

    DropBelow  = 130.0,

    Roll = 0.0,
}

local function placeNeckDecalByPath(defenderPath, modActorPath, material,
                                    attackerLocation)
    local succeeded, errorMessage = pcall(function()
        if not getLibraries() then
            return
        end

        local defender = nil
        local ok, found = pcall(function()
            return StaticFindObject(defenderPath)
        end)
        if ok and found then
            defender = found
        end
        if not defender or not defender:IsValid() then
            return
        end

        local origin = nil
        local mesh = defender.Mesh
        if mesh and mesh:IsValid() then
            origin = getSocketLocationOrNil(mesh, NECK_DECAL.Bone)
        end
        if not origin then
            origin = getActorLocationSnapshot(defender)
        end

        local groundLocation = {
            X = origin.X, Y = origin.Y, Z = origin.Z - NECK_DECAL.DropBelow,
        }
        local groundNormal = { X = 0.0, Y = 0.0, Z = 1.0 }

        local direction = { X = 1.0, Y = 0.0, Z = 0.0 }
        if attackerLocation then
            direction = vecNormalize(vecSub(origin, attackerLocation))
        end

        local spot = groundLocation
        if NECK_DECAL.TailOffset ~= 0.0 then
            local flat = { X = direction.X, Y = direction.Y, Z = 0.0 }
            local flatLength = math.sqrt(flat.X * flat.X + flat.Y * flat.Y)
            if flatLength > 0.01 then
                local shift = NECK_DECAL.Diameter * NECK_DECAL.TailOffset
                spot = {
                    X = groundLocation.X + (flat.X / flatLength) * shift,
                    Y = groundLocation.Y + (flat.Y / flatLength) * shift,
                    Z = groundLocation.Z,
                }
            end
        end

        placeGroundSpatter(modActorPath, spot, groundNormal,
            direction, material, NECK_DECAL.Diameter, NECK_DECAL.Depth,
            NECK_DECAL.Roll)
    end)

    if not succeeded then
        log(string.format("NECK DECAL ERROR: %s", tostring(errorMessage)))
    end
end

local function spawnNeckGroundDecal(defender, attacker)
    if not NECK_DECAL.Enabled then
        return
    end

    local defenderPath, modActorPath, material = nil, nil, nil
    local attackerLocation = nil

    local prepared, prepareError = pcall(function()
        if not defender or not defender:IsValid() then
            return
        end
        if not getLibraries() then
            return
        end

        local fullName = defender:GetFullName()
        if fullName then
            defenderPath = string.match(fullName, "^%S+%s+(.+)$") or fullName
        end

        local modActor = findBloodFXModActor(defender)
        if modActor and modActor:IsValid() then
            local modName = modActor:GetFullName()
            if modName then
                modActorPath = string.match(modName, "^%S+%s+(.+)$") or modName
            end
        end

        local materials = cachedDecalMaterials
        if materials == nil or cachedDecalMaterialOwner ~= modActor then
            materials = collectDecalMaterials(modActor)
        end
        if materials then

            local pick = NECK_DECAL.MaterialIndex + 1
            if pick < 1 or pick > #materials then
                pick = 1
            end
            material = materials[pick]
        end

        if attacker and attacker:IsValid() then
            attackerLocation = snapshotVector(attacker:K2_GetActorLocation())
        end
    end)

    if not prepared then
        log(string.format("NECK DECAL ERROR: %s", tostring(prepareError)))
        return
    end
    if not defenderPath or not modActorPath or not material then
        return
    end

    if NECK_DECAL.Delay > 0.0 then
        EnsurePumpAlive()
        Schedule(NECK_DECAL.Delay, function()
            placeNeckDecalByPath(defenderPath, modActorPath, material,
                attackerLocation)
        end)
    else
        placeNeckDecalByPath(defenderPath, modActorPath, material,
            attackerLocation)
    end
end

local NECK_BONE_NAME = "neck_01"

local HEAD_GORE_ATTACH = false

local HEAD_GORE_FX_POOLING = 0

local function playHeadGoreEffect(modActor, defender, location)
    local component = modActor.HeadGoreFX
    if not component or not component:IsValid() then
        log("BRIDGE: HeadGoreFX component is missing or invalid")
        return
    end

    local system = component
    local ok, inner = pcall(function()
        return component.Asset
    end)
    if ok and inner and inner:IsValid() then
        system = inner
    end
    if not system or not system:IsValid() then
        log("BRIDGE: HeadGoreFX has no valid Niagara asset")
        return
    end

    local rotation = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }

    if HEAD_GORE_ATTACH and defender and defender:IsValid() then
        local mesh = defender.Mesh
        if mesh and mesh:IsValid() then

            spawnFxAttached(system, mesh, NECK_BONE_NAME, location, rotation,
                1, HEAD_GORE_FX_POOLING)
            return
        end
    end

    spawnFxAtLocation(modActor, system, location, rotation, HEAD_GORE_FX_POOLING)
end

local function hideHeadBone(defender)

    local mesh = defender.Mesh
    if not mesh or not mesh:IsValid() then
        log("BRIDGE: defender Mesh is missing or invalid")
        return
    end

    mesh:HideBoneByName(FName("Head"), 0)
end

local NECK_SPRAY_PITCH = 0.0
local NECK_SPRAY_YAW = 0.0
local NECK_SPRAY_ROLL = 0.0

local NECK_FX_OFFSET_X = 4.0
local NECK_FX_OFFSET_Y = 0.0
local NECK_FX_OFFSET_Z = 0.0

local function playNeckBloodEffect(modActor, defender)

    if not FX_ENABLED then
        return
    end

    local ref = nil
    pcall(function()
        ref = modActor.NeckBloodFX
    end)
    if not ref or not ref:IsValid() then
        return
    end

    local system = ref
    pcall(function()
        local inner = ref.Asset
        if inner and inner:IsValid() then
            system = inner
        end
    end)

    if not system or not system:IsValid() then
        log("BRIDGE: NeckBloodFX has no valid Niagara system")
        return
    end

    local mesh = defender.Mesh
    if not mesh or not mesh:IsValid() then
        log("BRIDGE: defender Mesh is missing (neck blood)")
        return
    end

    local niagaraLib = getNiagaraLibrary()
    if not niagaraLib then
        log("BRIDGE: NiagaraFunctionLibrary was not found")
        return
    end

    niagaraLib:SpawnSystemAttached(
        system,
        mesh,
        FName(NECK_BONE_NAME),
        { X = NECK_FX_OFFSET_X, Y = NECK_FX_OFFSET_Y, Z = NECK_FX_OFFSET_Z },
        { Pitch = NECK_SPRAY_PITCH, Yaw = NECK_SPRAY_YAW, Roll = NECK_SPRAY_ROLL },
        0,
        FX_AUTO_DESTROY,
        true,
        FX_POOLING,
        true
    )
end

local HEAD_GORE_USE_HIT_FX = false

local HEAD_GORE_USE_ARTERIAL_FX = false

local NECK_HIT_FX_PITCH = 0.0
local NECK_HIT_FX_YAW = 0.0
local NECK_HIT_FX_ROLL = 0.0

local HEAD_GORE_SKIP_HIT_FX = true

local HEAD_GORE_NECK_FX_DELAY_TICKS = 0

local function playNeckHitBloodEffect(modActor, defender, isHeadGore)
    if not HEAD_GORE_USE_HIT_FX then
        return
    end

    if isHeadGore and HEAD_GORE_SKIP_HIT_FX then
        return
    end

    local particleSystem = getModActorAsset(modActor, "HitBloodFX", nil)
    if not particleSystem then
        return
    end

    local succeeded, errorMessage = pcall(function()
        if not getLibraries() then
            return
        end

        local mesh = defender.Mesh
        if not mesh or not mesh:IsValid() then
            log("BRIDGE: defender Mesh is missing (neck hit fx)")
            return
        end

        spawnFxAttached(
            particleSystem,
            mesh,
            NECK_BONE_NAME,
            { X = NECK_FX_OFFSET_X, Y = NECK_FX_OFFSET_Y, Z = NECK_FX_OFFSET_Z },
            { Pitch = NECK_HIT_FX_PITCH, Yaw = NECK_HIT_FX_YAW, Roll = NECK_HIT_FX_ROLL },
            0)
    end)

    if not succeeded then
        log(string.format("NECK HIT FX ERROR: %s", tostring(errorMessage)))
    end
end

local HEAD_GORE_SILENCE_VOICE = false

local HEAD_GORE_SILENCE_REPEATS = {}

local soundLibraries = nil

local function getSoundLibraries()
    if soundLibraries ~= nil then
        return soundLibraries
    end
    soundLibraries = {}

    local targets = {
        { name = "PalSoundUtility",   path = "/Script/Pal.Default__PalSoundUtility" },
        { name = "AkGameplayStatics", path = "/Script/AkAudio.Default__AkGameplayStatics" },
    }

    for _, target in ipairs(targets) do
        local ok, found = pcall(function()
            return StaticFindObject(target.path)
        end)
        if ok and found and found:IsValid() then
            soundLibraries[#soundLibraries + 1] = { name = target.name, object = found }
            log(string.format("VOICE: %s を取得しました", target.name))
        else
            log(string.format("VOICE: %s が見つかりません", target.name))
        end
    end

    return soundLibraries
end

local silenceTargets = {}
local silenceTargetCount = 0
local silenceHookLogged = {}

local function markForSilence(defender)
    if not defender or not defender:IsValid() then
        return
    end
    local ok, key = pcall(function()
        return defender:GetFullName()
    end)
    if not ok or not key then
        return
    end

    if silenceTargetCount > 16 then
        silenceTargets = {}
        silenceTargetCount = 0
    end

    silenceTargets[key] = true
    silenceTargetCount = silenceTargetCount + 1
end

local HEAD_GORE_SOUND_ENABLED = false
local HEAD_GORE_SOUND_PATH =
    "/Game/Pal/Sound/Events/SE/Pal/Pal_Effect/AKE_YakushimaBoss002_Death."
    .. "AKE_YakushimaBoss002_Death"
local HEAD_GORE_SOUND_DELAY = 0.0

local headGoreSound = nil
local headGoreSoundChecked = false

local function getHeadGoreSound()
    if headGoreSoundChecked then
        return headGoreSound
    end
    headGoreSoundChecked = true

    local ok, found = pcall(function()
        return StaticFindObject(HEAD_GORE_SOUND_PATH)
    end)
    if ok and found and found:IsValid() then
        headGoreSound = found
        log("SOUND: 効果音を取得しました(読み込み済み)")
        return headGoreSound
    end

    local okLoad, loaded = pcall(function()
        return LoadAsset(HEAD_GORE_SOUND_PATH)
    end)
    if okLoad and loaded then
        local okFind, again = pcall(function()
            return StaticFindObject(HEAD_GORE_SOUND_PATH)
        end)
        if okFind and again and again:IsValid() then
            headGoreSound = again
            log("SOUND: 効果音を読み込みました")
            return headGoreSound
        end
    end

    log(string.format("SOUND: 効果音が見つかりません %s", HEAD_GORE_SOUND_PATH))
    return nil
end

local function playHeadGoreSound(defender)
    if not HEAD_GORE_SOUND_ENABLED then
        return
    end
    if not defender or not defender:IsValid() then
        return
    end

    local event = getHeadGoreSound()
    if not event then
        return
    end

    for _, entry in ipairs(getSoundLibraries()) do
        if entry.name == "PalSoundUtility" then
            local ok, errorMessage = pcall(function()
                entry.object:PlayAkEventSoundByActor(defender, event)
            end)
            if not ok then
                log(string.format("SOUND ERROR: %s", tostring(errorMessage)))
            end
            return
        end
    end
end

local function silenceActorVoice(defender)
    if not HEAD_GORE_SILENCE_VOICE then
        return
    end
    if not defender or not defender:IsValid() then
        return
    end

    for _, entry in ipairs(getSoundLibraries()) do
        local ok, errorMessage = pcall(function()
            if entry.name == "PalSoundUtility" then
                entry.object:StopSoundByActor(defender)
            else
                entry.object:StopActor(defender)
            end
        end)
        if not ok then
            log(string.format("VOICE ERROR (%s): %s", entry.name, tostring(errorMessage)))
        end
    end
end

local function silenceByPath(path)
    if not path then
        return
    end
    local ok, found = pcall(function()
        return StaticFindObject(path)
    end)
    if ok and found then
        silenceActorVoice(found)
    end
end

local function silenceIfMarked(character, label)

    if silenceTargetCount == 0 then
        return
    end
    if not character or not character:IsValid() then
        return
    end
    local ok, key = pcall(function()
        return character:GetFullName()
    end)
    if not ok or not key then
        return
    end
    if not silenceTargets[key] then
        return
    end

    if not silenceHookLogged[label] then
        silenceHookLogged[label] = true
        log(string.format("VOICE: %s で追い停止しました", label))
    end
    silenceActorVoice(character)
end

local function triggerHeadGoreEffect(defender, hitLocation)

    local hitLocationSnapshot = snapshotVector(hitLocation)
    if not stillValid(defender) then
        return
    end
    local defenderRef = defender

    -- Prefer a live ModActor ref; fall back to cached path resolve.
    local modActorRef = cachedBloodFXModActor
    if not stillValid(modActorRef) then
        modActorRef = findBloodFXModActor(defender)
    end
    if not stillValid(modActorRef) then
        log("BRIDGE: BloodFX ModActor was not found in the defender's World")
        return
    end
    local modActorPath = cachedModActorPath

    runOnGameThread(function()
        local succeeded, errorMessage = pcall(function()
            if not stillValid(defenderRef) then
                return
            end
            local defender = defenderRef
            local modActor = stillValid(modActorRef) and modActorRef or resolveByPath(modActorPath)
            if not modActor then
                return
            end

            silenceActorVoice(defender)
            markForSilence(defender)

            playHeadGoreSound(defender)

            hideHeadBone(defender)

            playHeadGoreEffect(modActor, defender, hitLocationSnapshot)

            playNeckHitBloodEffect(modActor, defender, true)
        end)

        if not succeeded then
            log(string.format("BRIDGE ERROR: %s", tostring(errorMessage)))
        end
    end)

    if HEAD_GORE_USE_ARTERIAL_FX then
        if HEAD_GORE_NECK_FX_DELAY_TICKS <= 0 then
            runOnGameThread(function()
                local ok, err = pcall(function()
                    if not stillValid(defenderRef) then
                        return
                    end
                    local defender = defenderRef
                    local modActor = stillValid(modActorRef) and modActorRef or resolveByPath(modActorPath)
                    if not modActor then
                        return
                    end
                    playNeckBloodEffect(modActor, defender)
                end)
                if not ok then
                    log(string.format("NECK FX ERROR: %s", tostring(err)))
                end
            end)
        else
            local defenderPath = objectSoftPath(defenderRef)
            if defenderPath and modActorPath then
                EnsurePumpAlive()
                Schedule(HEAD_GORE_NECK_FX_DELAY_TICKS * PUMP_INTERVAL, function()
                    local ok, err = pcall(function()
                        local target = stillValid(defenderRef) and defenderRef or resolveByPath(defenderPath)
                        if not target then
                            return
                        end
                        local owner = stillValid(modActorRef) and modActorRef or resolveByPath(modActorPath)
                        if not owner then
                            return
                        end
                        playNeckBloodEffect(owner, target)
                    end)
                    if not ok then
                        log(string.format("NECK FX ERROR: %s", tostring(err)))
                    end
                end)
            end
        end
    end

    if HEAD_GORE_SILENCE_VOICE then
        local defenderPath = objectSoftPath(defenderRef)
        if defenderPath then
            EnsurePumpAlive()
            for _, delay in ipairs(HEAD_GORE_SILENCE_REPEATS) do
                Schedule(delay, function()
                    silenceByPath(defenderPath)
                end)
            end
        end
    end
end

local function flushLevelCaches()
    cachedBloodFXModActor = nil
    cachedModActorPath = nil
    cachedModActorWorldName = nil
    cachedDecalMaterials = nil
    cachedDecalMaterialSource = nil
    cachedDecalRolls = nil
    cachedDecalMaterialOwner = nil
    cachedBloodPoolClass = nil
    lastModActorSearchTime = nil
    modActorMissingLogged = false
    spatterTimeByActor = {}
    impactFxTimeByActor = {}
    spatterActorCount = 0
    decalsDeniedOn = {}
    scheduleQueue = {}
    bodyBloodNextIndex = {}
    bodyBloodActorCount = 0

    refPoseComponentCache = {}
    refPoseMeshCount = 0

    classAncestryCache = {}
    classAncestryCacheCount = 0
end

RegisterLoadMapPostHook(function()
    local succeeded, errorMessage = pcall(function()
        flushLevelCaches()
        shaderWarmupDone = false

        if SHADER_WARMUP.Enabled then
            EnsurePumpAlive()
            scheduleWarmupAttempt(1)
        end
    end)
    if not succeeded then
        log(string.format("CACHE FLUSH ERROR: %s", tostring(errorMessage)))
    end
end)

-- Death-path voice silence hooks disabled (extra UE4SS AVs during ragdoll).

local function handleDamageReact(
    Context,
    DamageResultParameter,
    DeadInfoParameter,
    IsDeadParameter,
    IsPartsBrokeParameter
)
    local damageResult = unwrap(DamageResultParameter)
    if not damageResult then
        return
    end

    local defender = damageResult.Defender
    if not stillValid(defender) then
        return
    end

    if not isBloodEligible(defender) then
        return
    end

    local human = isHumanNPC(defender)
    local isPal = (not human) and isPalCreature(defender)
    local isDead = unwrap(IsDeadParameter) == true
    local isWeak = tonumber(tostring(damageResult.BodyPartsType)) == 0
    local hitLocation = nil
    pcall(function()
        hitLocation = damageResult.HitLocation
    end)

    local attacker = nil
    pcall(function()
        attacker = damageResult.Attacker
    end)

    -- Snapshot only; all FX is scheduled off this native hook.
    local defenderRef = defender
    local attackerRef = attacker
    local hitSnap = snapshotVector(hitLocation)
    local isHeadshotKill = human and isDead and isWeak

    EnsurePumpAlive()
    Schedule(0.05, function()
        if not stillValid(defenderRef) then
            return
        end
        local defender = defenderRef
        local attacker = stillValid(attackerRef) and attackerRef or nil

        if isHeadshotKill then
            local okGore, goreErr = pcall(function()
                triggerHeadGoreEffect(defender, hitSnap)
            end)
            if not okGore then
                log(string.format("HEAD GORE SKIP: %s", tostring(goreErr)))
            end
        end

        if human then
            denyDecalsOnMesh(defender)
        end

        local okSpatter, spatterErr = pcall(function()
            triggerBloodSpatter(defender, attacker, hitSnap,
                isHeadshotKill, isPal, isDead)
        end)
        if not okSpatter then
            log(string.format("SPATTER SKIP: %s", tostring(spatterErr)))
        end

        if isDead then
            local okPool, poolErr = pcall(function()
                spawnBloodPool(defender, isHeadshotKill)
            end)
            if not okPool then
                log(string.format("POOL SKIP: %s", tostring(poolErr)))
            end
        end

        if isHeadshotKill then
            pcall(function()
                spawnNeckGroundDecal(defender, attacker)
            end)
        end
    end)
end

RegisterHook("/Script/Pal.PalDamageReactionComponent:MulticastDamageReact", function(
    Context,
    DamageResultParameter,
    DeadInfoParameter,
    IsDeadParameter,
    IsPartsBrokeParameter
)
    local succeeded, errorMessage = pcall(
        handleDamageReact,
        Context,
        DamageResultParameter,
        DeadInfoParameter,
        IsDeadParameter,
        IsPartsBrokeParameter)

    if not succeeded then
        log(string.format("HOOK ERROR: %s", tostring(errorMessage)))
    end
end)

local function scanLoadedCharacters()
    local succeeded, errorMessage = pcall(function()
        local actors = FindAllOf("PalCharacter")
        if not actors then
            log("SCAN: no PalCharacter instances found")
            return
        end

        local humanCount, palCount, playerCount, otherCount = 0, 0, 0, 0
        local samples = 0

        for _, actor in pairs(actors) do
            if actor and actor:IsValid() then
                local class = actor:GetClass()
                local ancestry = getClassAncestryNames(class)
                local top = ancestry[1] or "?"
                local human = isHumanNPC(actor)
                local player = isPlayerCharacter(actor)
                local pal = isPalCreature(actor)

                if human then
                    humanCount = humanCount + 1
                elseif player then
                    playerCount = playerCount + 1
                elseif pal then
                    palCount = palCount + 1
                else
                    otherCount = otherCount + 1
                end

                if samples < 24 then
                    samples = samples + 1
                    log(string.format(
                        "SCAN #%d class=%s human=%s pal=%s player=%s ancestry=%s",
                        samples,
                        top,
                        tostring(human),
                        tostring(pal),
                        tostring(player),
                        table.concat(ancestry, " > ")))
                end
            end
        end

        log(string.format(
            "SCAN totals: human=%d pal=%d player=%d other=%d",
            humanCount, palCount, playerCount, otherCount))
    end)

    if not succeeded then
        log(string.format("SCAN ERROR: %s", tostring(errorMessage)))
    end
end

local okKeybind, keybindError = pcall(function()
    RegisterKeyBind(Key.F8, { ModifierKey.CONTROL }, function()
        ExecuteInGameThread(function()
            scanLoadedCharacters()
        end)
    end)
end)
if not okKeybind then
    log(string.format("KEYBIND: Ctrl+F8 unavailable (%s)", tostring(keybindError)))
end

StartPumpLoop()

log("Loaded. Blood for human NPCs + pals. Decapitation: humans only.")
log("Stability 1.0.5: fixed FX pump thrash; hit Niagara + neck geyser off (decals/pools/decap keep).")
log("Press Ctrl+F8 to scan loaded characters / class ancestry.")
log("Blood spatter is active (backward toward the attacker, sticks to floors).")
log("Do NOT load this alongside the original Blood Splatter mod.")
