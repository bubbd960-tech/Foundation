--!strict
--!optimize 2
--!native

--[[Module Ceated by Quill, quick an user friendly code, this module was mainly created for QoL usage.]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

type Fn = (...any) -> ...any
type Map<K, V> = { [K]: V }
type Array<T> = { [number]: T }

local QoL = {}

local FreeThreads: Array<thread> = {}

local function runCallback(callback: Fn, thread: thread, ...: any)
	local result = callback(...)
	table.insert(FreeThreads, thread)
end

local function yielder()
	while true do
		runCallback(coroutine.yield())
	end
end

local function spawn<T...>(callback: (T...) -> (), ...: T...)
	local thread
	if #FreeThreads > 0 then
		thread = table.remove(FreeThreads, #FreeThreads)
	else
		thread = coroutine.create(yielder)
		coroutine.resume(thread)
	end
	task.spawn(thread, callback, thread, ...)
end

local Connection = {}
Connection.__index = Connection

type Connection = typeof(setmetatable({} :: {
	_connected: boolean,
	_signal: any,
	_node: any,
}, Connection))

function Connection.new(signal: any, node: any): Connection
	return setmetatable({
		_connected = true,
		_signal = signal,
		_node = node,
	}, Connection)
end

function Connection:Disconnect()
	if not self._connected then return end
	self._connected = false
	if self._signal._head == self._node then
		self._signal._head = self._node.next
	else
		local prev = self._signal._head
		while prev and prev.next ~= self._node do
			prev = prev.next
		end
		if prev then
			prev.next = self._node.next
		end
	end
end

local Signal = {}
Signal.__index = Signal

type Signal<T...> = typeof(setmetatable({} :: {
	_head: any,
}, Signal))

function Signal.new()
	return setmetatable({ _head = nil }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local node = { fn = fn, next = self._head }
	self._head = node
	return Connection.new(self, node)
end

function Signal:Fire(...: any)
	local node = self._head
	while node do
		spawn(node.fn, ...)
		node = node.next
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	self._head = nil
end

QoL.Signal = Signal

local Janitor = {}
Janitor.__index = Janitor

type Janitor = typeof(setmetatable({} :: {
	_objects: Array<any>,
}, Janitor))

function Janitor.new()
	return setmetatable({ _objects = {} }, Janitor)
end

function Janitor:Add<T>(object: T, methodName: string?, index: any?): T
	if index then
		self:Remove(index)
	end
	local cleanup = object
	if methodName then
		cleanup = function()
			(object :: any)[methodName](object)
		end
	elseif typeof(object) == "function" then
		cleanup = object
	elseif typeof(object) == "RBXScriptConnection" then
		cleanup = function()
			(object :: any):Disconnect()
		end
	elseif typeof(object) == "Instance" then
		cleanup = function()
			(object :: any):Destroy()
		end
	elseif type(object) == "table" and (object :: any).Destroy then
		cleanup = function()
			(object :: any):Destroy()
		end
	end

	if index then
		self._objects[index] = cleanup
	else
		table.insert(self._objects, cleanup)
	end
	return object
end

function Janitor:Remove(index: any)
	local object = self._objects[index]
	if object then
		if type(object) == "function" then
			object()
		end
		self._objects[index] = nil
	end
end

function Janitor:Cleanup()
	for index, object in pairs(self._objects) do
		if type(object) == "function" then
			object()
		end
		self._objects[index] = nil
	end
end

function Janitor:Destroy()
	self:Cleanup()
end

QoL.Janitor = Janitor

local InstanceUtil = {}

function InstanceUtil.WaitForChildOfClass(parent: Instance, className: string, timeout: number?): Instance?
	local start = os.clock()
	local result = parent:FindFirstChildOfClass(className)
	while not result do
		if timeout and (os.clock() - start) > timeout then
			return nil
		end
		task.wait(0.1)
		result = parent:FindFirstChildOfClass(className)
	end
	return result
end

function InstanceUtil.GetChildrenOfClass(parent: Instance, className: string): Array<Instance>
	local children = parent:GetChildren()
	local results = table.create(#children)
	local count = 0
	for _, child in ipairs(children) do
		if child:IsA(className) then
			count += 1
			results[count] = child
		end
	end
	return results
end

function InstanceUtil.DeepFind(parent: Instance, name: string, maxDepth: number?): Instance?
	local function search(current: Instance, depth: number): Instance?
		if maxDepth and depth > maxDepth then return nil end
		local target = current:FindFirstChild(name)
		if target then return target end

		for _, child in ipairs(current:GetChildren()) do
			local found = search(child, depth + 1)
			if found then return found end
		end
		return nil
	end
	return search(parent, 0)
end

function InstanceUtil.Require(moduleScript: ModuleScript, timeout: number?): any
	local thread = coroutine.running()
	local loaded = false

	task.spawn(function()
		local success, result = pcall(require, moduleScript)
		if not loaded then
			loaded = true
			if success then
				task.spawn(thread, result)
			else
				error(result)
			end
		end
	end)

	if timeout then
		task.delay(timeout, function()
			if not loaded then
				loaded = true
				task.spawn(thread, nil)
			end
		end)
	end

	return coroutine.yield()
end

QoL.Instance = InstanceUtil

local TableUtil = {}

function TableUtil.DeepCopy<T>(t: T): T
	if type(t) ~= "table" then return t end
	local new = table.create(#(t :: any))
	for k, v in pairs(t :: any) do
		new[k] = TableUtil.DeepCopy(v)
	end
	return new :: T
end

function TableUtil.Reconcile(target: Map<any, any>, template: Map<any, any>)
	for k, v in pairs(template) do
		if target[k] == nil then
			if type(v) == "table" then
				target[k] = TableUtil.DeepCopy(v)
			else
				target[k] = v
			end
		elseif type(target[k]) == "table" and type(v) == "table" then
			TableUtil.Reconcile(target[k], v)
		end
	end
end

function TableUtil.FastRemove(t: Array<any>, index: number)
	local n = #t
	t[index] = t[n]
	t[n] = nil
end

function TableUtil.Map(t: Array<any>, mapper: (any) -> any): Array<any>
	local new = table.create(#t)
	for i, v in ipairs(t) do
		new[i] = mapper(v)
	end
	return new
end

function TableUtil.Filter(t: Array<any>, predicate: (any) -> boolean): Array<any>
	local new = {}
	for _, v in ipairs(t) do
		if predicate(v) then
			table.insert(new, v)
		end
	end
	return new
end

QoL.Table = TableUtil

local MathUtil = {}

function MathUtil.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.InverseLerp(a: number, b: number, v: number): number
	return (v - a) / (b - a)
end

function MathUtil.Remap(v: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return outMin + (v - inMin) * (outMax - outMin) / (inMax - inMin)
end

function MathUtil.GetDistanceSquared(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return dx*dx + dy*dy + dz*dz
end

QoL.Math = MathUtil

local Async = {}

function Async.Promise(executor: (resolve: (any) -> (), reject: (any) -> ()) -> ())
	local self = {
		_status = "Pending",
		_value = nil,
		_queue = {},
	}

	local function resolve(val)
		if self._status ~= "Pending" then return end
		self._status = "Resolved"
		self._value = val
		for _, cb in ipairs(self._queue) do
			if cb.onResolved then spawn(cb.onResolved, val) end
		end
	end

	local function reject(err)
		if self._status ~= "Pending" then return end
		self._status = "Rejected"
		self._value = err
		for _, cb in ipairs(self._queue) do
			if cb.onRejected then spawn(cb.onRejected, err) end
		end
	end

	function self:AndThen(onResolved, onRejected)
		if self._status == "Resolved" then
			spawn(onResolved, self._value)
		elseif self._status == "Rejected" then
			if onRejected then spawn(onRejected, self._value) end
		else
			table.insert(self._queue, {onResolved = onResolved, onRejected = onRejected})
		end
		return self
	end

	function self:Catch(onRejected)
		return self:AndThen(nil, onRejected)
	end

	function self:Await()
		while self._status == "Pending" do
			RunService.Heartbeat:Wait()
		end
		return self._status == "Resolved", self._value
	end

	spawn(executor, resolve, reject)
	return self
end

function Async.Retry(retries: number, fn: () -> any, ...: any)
	local current = 0
	while current < retries do
		local success, result = pcall(fn, ...)
		if success then return result end
		current += 1
		task.wait(1)
	end
	error("Max retries reached")
end

QoL.Async = Async

local Net = {}
Net._cache = {}

function Net.Pack(...: any): string
	return HttpService:JSONEncode({...})
end

function Net.Unpack(data: string): Array<any>
	return HttpService:JSONDecode(data)
end

function Net.Remote(name: string): RemoteEvent
	if Net._cache[name] then return Net._cache[name] end
	local r
	if RunService:IsServer() then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = game:GetService("ReplicatedStorage")
	else
		r = game:GetService("ReplicatedStorage"):WaitForChild(name, 10)
		if not r then error("Remote not found: " .. name) end
	end
	Net._cache[name] = r
	return r
end

QoL.Net = Net

local BufferUtil = {}

function BufferUtil.WriteString(b: buffer, offset: number, str: string): number
	local len = #str
	buffer.writeu16(b, offset, len)
	buffer.writestring(b, offset + 2, str)
	return offset + 2 + len
end

function BufferUtil.ReadString(b: buffer, offset: number): (string, number)
	local len = buffer.readu16(b, offset)
	local str = buffer.readstring(b, offset + 2, len)
	return str, offset + 2 + len
end

QoL.Buffer = BufferUtil

local State = {}
State.__index = State

function State.new<T>(initialValue: T)
	local self = setmetatable({
		_value = initialValue,
		Changed = Signal.new()
	}, State)
	return self
end

function State:Get(): any
	return self._value
end

function State:Set(newValue: any)
	if self._value == newValue then return end
	local old = self._value
	self._value = newValue
	self.Changed:Fire(newValue, old)
end

function State:Bind(callback: (any) -> ())
	callback(self._value)
	return self.Changed:Connect(callback)
end

function State:Destroy()
	self.Changed:Destroy()
	setmetatable(self, nil)
end

QoL.State = State

local Pool = {}
Pool.__index = Pool

function Pool.new(template: Instance, size: number)
	local self = setmetatable({
		_template = template,
		_available = table.create(size),
		_container = nil
	}, Pool)

	if RunService:IsClient() then
		self._container = Instance.new("Folder")
		self._container.Name = "Pool_" .. template.Name
		self._container.Parent = workspace
	end

	for i = 1, size do
		local obj = template:Clone()
		if self._container then obj.Parent = self._container end
		table.insert(self._available, obj)
	end

	return self
end

function Pool:Get(): Instance
	local obj = table.remove(self._available)
	if not obj then
		obj = self._template:Clone()
	end
	if self._container then obj.Parent = nil end
	return obj
end

function Pool:Return(obj: Instance)
	if self._container then obj.Parent = self._container end
	table.insert(self._available, obj)
end

function Pool:Destroy()
	if self._container then self._container:Destroy() end
	for _, obj in ipairs(self._available) do
		obj:Destroy()
	end
	self._available = {}
end

QoL.Pool = Pool

local Octree = {}
Octree.__index = Octree

function Octree.new(regionSize: number)
	return setmetatable({
		_regionSize = regionSize,
		_objects = {}
	}, Octree)
end

function Octree:Insert(object: any, position: Vector3)
	local x = math.floor(position.X / self._regionSize)
	local y = math.floor(position.Y / self._regionSize)
	local z = math.floor(position.Z / self._regionSize)
	local key = x .. ":" .. y .. ":" .. z

	if not self._objects[key] then
		self._objects[key] = {}
	end
	table.insert(self._objects[key], {obj = object, pos = position})
end

function Octree:SearchRadius(position: Vector3, radius: number): Array<any>
	local results = {}
	local rSq = radius * radius
	local range = math.ceil(radius / self._regionSize)

	local cx = math.floor(position.X / self._regionSize)
	local cy = math.floor(position.Y / self._regionSize)
	local cz = math.floor(position.Z / self._regionSize)

	for x = cx - range, cx + range do
		for y = cy - range, cy + range do
			for z = cz - range, cz + range do
				local key = x .. ":" .. y .. ":" .. z
				local cell = self._objects[key]
				if cell then
					for _, item in ipairs(cell) do
						if MathUtil.GetDistanceSquared(item.pos, position) <= rSq then
							table.insert(results, item.obj)
						end
					end
				end
			end
		end
	end
	return results
end

QoL.Octree = Octree


return QoL
