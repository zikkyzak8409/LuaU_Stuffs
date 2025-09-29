--Types segment


--Service segment
local runService = game:GetService('RunService')
local contextActionService = game:GetService('ContextActionService')
local playerService = game:GetService('Players')

local abstract = {} --> abstraction for easy access

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

local function makeNewTrack(
	animId : string,
	priorityLevel : Enum.AnimationPriority?
) : AnimationTrack?
	
	local track = registeredIds[animId]
	
	if track then
		track = priorityLevel or Enum.AnimationPriority.Action
		return track
	end
	
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

function states:StartState(
	stateName : string,
	animSpeed : number?,
	isAction : boolean?
) : ()
	if feedLock then return end
	if activeAction then return end
	if isAction then activeAction = true end
	if not stateName then warn('states start state invalid statename') return end
	
	local targTrack = anims[stateName]
	if not targTrack then warn('states start state invalid statename - no targ track') return end
	
	activeAnimSpeed = animSpeed or activeAnimSpeed
	
	local activeTrack = activeAnim and activeAnim.Track
	if activeTrack == targTrack.Track then return end --Ignore same anim
	
	if activeTrack then
		
		activeTrack:Stop(.05)
		activeAnimSpeed = 1
		if activeAnim.Connection then activeAnim.Connection:Disconnect() end
		
		local endFunc : (char : Model) -> () ? = activeAnim.EndFunc
		if endFunc then endFunc(abstract.char) end
	end
	
	local newTrack : AnimationTrack? = targTrack.Track
	local startFunc : (char : Model) -> () ? = targTrack.StartFunc
	
	newTrack:Play()
	targTrack.Connection = runService.Heartbeat:Connect(function()
		newTrack:AdjustSpeed(activeAnimSpeed)
	end)
	
	if startFunc then startFunc(abstract.char) end
	
	activeAnim = targTrack
	
	return true
end

function states:AddState(
	stateName : string,
	animId : string,
	priority : Enum.AnimationPriority?,
	stateStartFunc : (char: Model) -> () ?,
	stateEndFunc : (char : Model) -> () ?
)
	assert(stateName and animId, `states add state invalid args`)
	local targTrack = makeNewTrack(animId, priority)
	assert(targTrack, `invalid targ track id {animId}`)
	
	anims[stateName] = {
		Track = targTrack,
		StartFunc = stateStartFunc,
		EndFunc = stateEndFunc,
		Connection = nil
	}
	
	return targTrack.Ended
end

--for easy action binding or manual (whatever preferred)
function states:AddAction(
	actionName : string,
	animId : string,
	priority : Enum.AnimationPriority,
	coolDown : number?,
	keybindParams : {Enum.KeyCode | Enum.UserInputType | Enum.UserInputState}?,
	animSpeed : number?,
	stateStartFunc : (char: Model) -> () ?,
	stateEndFunc : (char : Model) -> () ?
)
	
	if not actionName then warn('states add action no action name') return end
	local targTrack = makeNewTrack(animId, priority) --this overwrites priority, maybe decouple later
	assert(actionName and animId and priority, `states add action requires name, id and priority`)
	coolDown = coolDown or 0
	
	local cd = false
	
	--if auto binding
	for i=1, #keybindParams do
		actions[`{actionName}{i}`] = contextActionService:BindAction(`{actionName}{i}`, function(inputActionName, inputState, _inputObject)
			if inputState ~= Enum.UserInputState.Begin then return end
			if activeAction then return end
			if cd then return end
			
			states:StartState(actionName,animSpeed or 1, true)
			task.delay(coolDown, function()
				cd = false
				activeAction = nil
			end)
			
			cd = true
		end, false, keybindParams[i])
	end
	
	anims[actionName] = {
		Track = targTrack,
		StartFunc = stateStartFunc,
		EndFunc = stateEndFunc,
		Connection = nil
	}
	
	return actionName
end

function states:ClearAllActions(
	withEndFunc : boolean?
) : ()
	
	local activeAction = activeAction and activeAction.Track
	
	if activeAction then
		activeAction:Stop(.05)

		if withEndFunc then
			local endFunc : (char : Model) -> () ? = activeAction.EndFunc
			if endFunc then endFunc(abstract.char) end
		end
	end
	
	--unbind auto bound actions
	for _, binding in actions do
		contextActionService:UnbindAction(binding)
	end

	actions = {}
	return true
end

function states:ClearAllMovementAnims(withEndFunc : boolean?) : ()
	local activeTrack = activeAnim and activeAnim.Track

	if activeTrack then
		activeTrack:Stop(.05)

		if withEndFunc then
			local endFunc : (char : Model) -> () ? = activeAnim.EndFunc
			if endFunc then endFunc(abstract.char) end
		end
	end

	anims = {}
	return true
end

function states:ClearAllAnim(withEndFunc : boolean?) : ()
	
	states:ClearAllActions(withEndFunc)
	states:ClearAllMovementAnims(withEndFunc)
	
	return true
end

function states:HaltAllAnim(withEndFunc : boolean) : ()
	activeAction = false
	local activeTrack = activeAnim and activeAnim.Track
	
	if activeTrack then
		activeTrack:Stop(.05)

		if withEndFunc then
			local endFunc : (char : Model) -> () ? = activeAnim.EndFunc
			if endFunc then endFunc(abstract.char) end
		end
	end
	
	return true
end

function states:LockAllAnim(haltAll : boolean?, haltWithEndFunc : boolean?) : ()
	feedLock = true
	if haltAll then states:HaltAllAnim(haltWithEndFunc) end
end

return states
