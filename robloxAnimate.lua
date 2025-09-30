--Types segment


--Service segment
local runService = game:GetService('RunService')
local contextActionService = game:GetService('ContextActionService')
local playerService = game:GetService('Players')

local abstract = {} --> abstraction for easy access // can be used to rewrite heirarchy for custom rigs / use animation controller

abstract.player = playerService.LocalPlayer
abstract.char = abstract.player.Character or abstract.player.CharacterAdded:Wait()
abstract.humanoid = abstract.char:WaitForChild('Humanoid') :: Humanoid
abstract.hrp = abstract.char:WaitForChild('HumanoidRootPart') :: BasePart
abstract.animator = abstract.humanoid:WaitForChild('Animator') :: Animator

--main vars
local states = {}
local activeAnim = nil
local activeAction = nil
local activeAnimSpeed = 1
local feedLock = nil --> prevent all future anims from playing

--vars for dod
local anims = {}
local registeredIds = {}
local actions = {}

--[[
to lock any anims from being input (a full animation lock)
returns none
]]
function states.LockAllAnim(
	haltAll : boolean?,
	haltWithEndFunc : boolean?,
	fadeOutTime : number?
) : ()

	feedLock = true
	if haltAll then states.HaltAllAnim(haltWithEndFunc, fadeOutTime) end

	return
end

--[[
to unlock anim input procedure
returns none
]]
function states.UnlockAllAnim() : ()
	
	feedLock = nil
	return
end

--[[
new track making -> make new track if it does not exist / return existing track
returns animation track
]]
local function makeNewTrack(
	animId : string,
	priorityLevel : Enum.AnimationPriority?
) : AnimationTrack?
	
	local track = registeredIds[animId]
	
	if track then --overwrite priority if track already exists
		track.Priority = priorityLevel or Enum.AnimationPriority.Action
		return track
	end
	
	--protects from any causes of error
	xpcall(function()
		
		local animation = Instance.new('Animation')
		animation.AnimationId = animId
		
		track = abstract.animator:LoadAnimation(animation)
		track.Priority = priorityLevel or Enum.AnimationPriority.Movement

		registeredIds[animId] = track
		
	end, function(err)
		warn('states : make new track error - ', err)
	end)
	
	return track
end

--[[
start state (main function)
returns true=success, false/nil=fail
]]
function states.StartState(
	stateName : string,
	animSpeed : number?,
	fadeOutTime : number?,
	isAction : boolean?
) : ()
	
	if feedLock then return end
	if activeAction then return end
	if isAction then activeAction = true end
	if not stateName then warn('states start state invalid statename') return end
	
	local targTrack = anims[stateName]
	
	if not targTrack then warn(`states start state invalid statename - no targ track, {stateName}`) return end
	
	activeAnimSpeed = animSpeed or activeAnimSpeed
	
	local activeTrack = activeAnim and activeAnim.Track
	if activeTrack == targTrack.Track then return end --Ignore same anim
	
	if activeTrack then
		
		states.LockAllAnim(false,false,nil) --lock all anim for transitioning
		
		activeTrack:Stop(fadeOutTime or .05)
		activeAnimSpeed = 1
		if activeAnim.Connection then activeAnim.Connection:Disconnect() end
		
		local endFunc : (char : Model) -> () ? = activeAnim.EndFunc
		if endFunc then endFunc(abstract.char) end
	end
	
	local newTrack : AnimationTrack? = targTrack.Track
	local startFunc : (char : Model) -> () ? = targTrack.StartFunc
	
	newTrack:Play(fadeOutTime or .05)
	targTrack.Connection = runService.Heartbeat:Connect(function()
		newTrack:AdjustSpeed(activeAnimSpeed)
	end)
	
	if startFunc then startFunc(abstract.char) end
	
	activeAnim = targTrack
	
	--delay input of next anim until this one is done
	task.delay(fadeOutTime or .05, states.UnlockAllAnim)
	
	return true
end

--[[
append an animation state -> has function hooks for start/end of anims
returns animation track
]]
function states.AddState(
	stateName : string,
	animId : string,
	priority : Enum.AnimationPriority?,
	stateStartFunc : (char: Model) -> () ?,
	stateEndFunc : (char : Model) -> () ?
) : AnimationTrack?
	
	assert(stateName and animId, `states add state invalid args, {stateName}, {animId}`)
	local targTrack = makeNewTrack(animId, priority)
	assert(targTrack, `invalid targ track id {animId}`)
	
	anims[stateName] = {
		Track = targTrack,
		StartFunc = stateStartFunc,
		EndFunc = stateEndFunc,
		Connection = nil
	}
	
	return targTrack --maybe useful return?
end

--[[
for easy action binding or manual (whatever preferred) -> has start/end hooks (could be used for remote event transmission)
returns actionName
]]
function states.AddAction(
	actionName : string,
	animId : string,
	priority : Enum.AnimationPriority,
	coolDown : number?,
	keybindParams : {Enum.KeyCode | Enum.UserInputType | Enum.UserInputState}?,
	animSpeed : number?,
	stateStartFunc : (char: Model) -> () ?,
	stateEndFunc : (char : Model) -> () ?,
	fadeOutTime : number?
) : string? --> return action name
	
	if not actionName then warn('states add action no action name') return end
	local targTrack = makeNewTrack(animId, priority) --this overwrites priority, maybe decouple later
	assert(actionName and animId and priority, `states add action requires name, id and priority`)
	coolDown = coolDown or 0
	
	local cd = false
	
	--if not auto binding
	if not keybindParams then
		anims[actionName] = {
			
			IsAction = true, --> to separate actions/movement anims
			Track = targTrack,
			StartFunc = stateStartFunc,
			EndFunc = stateEndFunc,
			Connection = nil
			
		}
		return actionName
	end
	
	--if auto binding -> uses contextactionservice
	for i=1, #keybindParams do
		actions[`{actionName}{i}`] = contextActionService:BindAction(`{actionName}{i}`, function(inputActionName, inputState, _inputObject)
			if inputState ~= Enum.UserInputState.Begin then return end
			if activeAction then return end
			if cd then return end
			
			states.StartState(actionName,animSpeed or 1,fadeOutTime or .05, true)
			task.delay(coolDown, function()
				cd = false
				activeAction = nil
			end)
			
			cd = true
		end, false, keybindParams[i])
	end
	
	anims[actionName] = {
		
		IsAction = true,
		Track = targTrack,
		StartFunc = stateStartFunc,
		EndFunc = stateEndFunc,
		Connection = nil
	}
	
	return actionName
end

--for easy action unbinding
function states.ClearAllActions(
	withEndFunc : boolean?,
	fadeOutTime : number?
) : ()
	
	local activeAction = activeAction and activeAction.Track
	
	if activeAction then
		activeAction:Stop(fadeOutTime or .05)

		if withEndFunc then
			local endFunc : (char : Model) -> () ? = activeAction.EndFunc
			if endFunc then endFunc(abstract.char) end
		end
	end
	
	--unbind auto bound actions
	for _, binding in actions do
		contextActionService:UnbindAction(binding)
	end
	
	--remove actions from anims table
	for index, animTable in anims do
		if animTable.IsAction == nil then continue end
		
		anims[index] = nil
	end

	actions = {}
	return true
end

--for removing movement anims
function states.ClearAllMovementAnims(
	withEndFunc : boolean?,
	fadeOutTime : number?
) : ()
	
	local activeTrack = activeAnim and activeAnim.Track

	if activeTrack then
		activeTrack:Stop(fadeOutTime or .05)

		if withEndFunc then
			local endFunc : (char : Model) -> () ? = activeAnim.EndFunc
			if endFunc then endFunc(abstract.char) end
		end
	end
	
	for index, v in anims do
		if v.IsAction then continue end
		
		anims[index] = nil
	end
	
	return true
end

--convenient for full removal of anims
function states.ClearAllAnim(
	withEndFunc : boolean?,
	fadeOutTime : number?
) : ()
	
	states.ClearAllActions(withEndFunc, fadeOutTime)
	states.ClearAllMovementAnims(withEndFunc, fadeOutTime)
	
	return true
end

--force stop all anims, useful when loading in a new anim / applying an external anim
function states.HaltAllAnim(
	withEndFunc : boolean,
	fadeOutTime : number?
) : ()
	
	activeAction = false
	local activeTrack = activeAnim and activeAnim.Track
	
	if activeTrack then
		activeTrack:Stop(fadeOutTime or .05)

		if withEndFunc then
			local endFunc : (char : Model) -> () ? = activeAnim.EndFunc
			if endFunc then endFunc(abstract.char) end
		end
	end
	
	return true
end

return states
