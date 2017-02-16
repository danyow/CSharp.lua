--[[
Copyright 2016 YANG Huan (sy.yanghuan@gmail.com).
Copyright 2016 Redmoon Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]

local System = System
local throw = System.throw
local Char = System.Char
local Int = System.Int
local Double = System.Double
local String = System.String
local Boolean = System.Boolean
local Delegate = System.Delegate
local InvalidCastException = System.InvalidCastException
local ArgumentNullException = System.ArgumentNullException
local TypeLoadException = System.TypeLoadException

local type = type
local getmetatable = getmetatable
local tinsert = table.insert
local ipairs = ipairs
local select = select
local unpack = table.unpack

local Type = {}
local numberType = setmetatable({ c = Double, name = "Number", fullName = "System.Number" }, Type)
local types = {
    [Char] = numberType,
    [Int] = numberType,
    [Double] = numberType,
}

local function typeof(cls)
    assert(cls)
    local type = types[cls]
    if type == nil then
        type = setmetatable({ c = cls }, Type)
        types[cls] = type
    end
    return type
end

local function getType(obj)
    return typeof(getmetatable(obj))
end

System.Object.GetType = getType
System.typeof = typeof

local function isGenericName(name)
    return name:byte(#name) == 93
end

function Type.getIsGenericType(this)
    return isGenericName(this.c.__name__)
end

function Type.getIsEnum(this)
    return this.c.__kind__ == "E"
end

function Type.getName(this)
    local name = this.name
    if name == nil then
        local clsName = this.c.__name__
        local pattern = isGenericName(clsName) and "^.*()%.(.*)%[.+%]$" or "^.*()%.(.*)$"
        name = clsName:gsub(pattern, "%2")
        this.name = name
    end
    return name
end

function Type.getFullName(this)
    local fullName = this.fullName
    if fullName == nil then
        fullName = this.c.__name__
        this.fullName = fullName
    end
    return fullName
end

function Type.getNamespace(this)
    local namespace = this.namespace
    if namespace == nil then
        local clsName = this.c.__name__
        local pattern = isGenericName(clsName) and "^(.*)()%..*%[.+%]$" or "^(.*)()%..*$"
        namespace = clsName:gsub(pattern, "%1")
        this.namespace = namespace
    end
    return namespace
end

local function getBaseType(this)
    local baseType = this.baseType
    if baseType == nil then
        local baseCls = this.c.__base__
        if baseCls ~= nil then
            baseType = typeof(baseCls)
            this.baseType = baseType
        end
    end 
    return baseType
end

Type.getBaseType = getBaseType

local function isSubclassOf(this, c)
    local p = this
    if p == c then
        return false
    end
    while p ~= nil do
        if p == c then
            return true
        end
        p = getBaseType(p)
    end
    return false
end

Type.IsSubclassOf = isSubclassOf

local function getIsInterface(this)
    return this.c.__kind__ == "I"
end

Type.getIsInterface = getIsInterface

local function getIsValueType(this)
    return this.c.__kind__ == "S"
end

Type.getIsValueType = getIsValueType

local function getInterfaces(this)
    local interfaces = this.interfaces
    if interfaces == nil then
        interfaces = {}
        local interfacesCls = this.c.__interfaces__
        if interfacesCls ~= nil then
            for _, i in ipairs(interfacesCls) do
                tinsert(interfaces, typeof(i))
            end
        end
        this.interfaces = System.arrayFromTable(interfaces, Type)
    end
    return interfaces
end

function Type.getInterfaces(this)
    local interfaces = getInterfaces(this)
    local array = {}
    for _, i in ipairs(interfaces) do
        tinsert(array, i)
    end    
    return System.arrayFromTable(array, Type)
end

local function implementInterface(this, ifaceType)
    local t = this
    while t ~= nil do
        local interfaces = getInterfaces(this)
        if interfaces ~= nil then
            for _, i in ipairs(interfaces) do
                if i == ifaceType or implementInterface(i, ifaceType) then
                    return true
                end
            end
        end
        t = getBaseType(t)
    end
    return false
end

local function isAssignableFrom(this, c)
    if c == nil then 
        return false 
    end
    if this == c then 
        return true 
    end
    if getIsInterface(this) then
        return implementInterface(c, this)
    else 
        return isSubclassOf(c, this)
    end
end 

Type.IsAssignableFrom = isAssignableFrom

function Type.IsInstanceOfType(this, obj)
    if obj == nil then
        return false 
    end
    return isAssignableFrom(this, obj:GetType())
end

function Type.ToString(this)
    return this.c.__name__
end

local function getclass(className)
    local scope = _G
    local starInx = 1
    while true do
        local pos = className:find("%.", starInx) or 0
        local name = className:sub(starInx, pos -1)
        if pos ~= 0 then
            local t = scope[name]
            if t == nil then
                return nil
            end
            scope = t
        else
            return scope[name]
        end
        starInx = pos + 1
    end
end

System.getclass = getclass

function Type.GetTypeStatic(typeName, throwOnError, ignoreCase)
    if typeName == nil then
        throw(ArgumentNullException("typeName"))
    end
    if #typeName == 0 then
        if throwOnError then
            throw(TypeLoadException("Arg_TypeLoadNullStr"))
        end
        return nil
    end
    assert(not ignoreCase, "NoSupport")
    local cls = getclass(typeName)
    if cls ~= nil then
        return typeof(cls)
    end 
    if throwOnError then
        throw(TypeLoadException(typeName .. ": failed to load."))
    end
    return nil    
end

System.define("System.Type", Type)

function isInterfaceOf(t, ifaceType)
    local interfaces = t.__interfaces__
    if interfaces then
       for _, i in ipairs(interfaces) do
           if i == ifaceType or  isInterfaceOf(i, ifaceType) then
               return true
           end
       end 
    end
    return false
end

function isTypeOf(obj, cls)    
    local typename = type(obj)
    if typename == "number" then
        return cls == Int or cls == Double or cls == Char
    elseif typename == "string" then
        return cls == String
    elseif typename == "table" then   
        if getmetatable(obj) == cls then
            return true
        end
        if cls.__kind__ == "I" then
            return isInterfaceOf(obj, cls)
        else
            local base = obj.__base__
            while base ~= nil do
                if base == cls then
                    return true
                end
                base = base.__base__
            end
        end
    elseif typename == "boolean" then
        return cls == Boolean
    else 
        return cls == Delegate
    end
end

function System.is(obj, cls)
    return obj ~= nil and isTypeOf(obj, cls)
end 

function System.as(obj, cls)
    if obj ~= nil and isTypeOf(obj, cls) then
       return obj
    end
    return nil
end

function System.cast(cls, obj)
    if obj == nil then
        if cls.__kind__ ~= "S" then
            return nil
        end
    else 
        if isTypeOf(obj, cls) then
            return obj
        end
    end
    throw(InvalidCastException(), 1)
end

function System.CreateInstance(type, ...)
    if type == nil then
        throw(ArgumentNullException("type"))
    end
    if getmetatable(type) ~= Type then   -- is T
        return type()
    end
    local len = select("#", ...)
    if len == 1 then
        local args = ...
        if System.isArrayLike(args) then
            local t = {}
            for k, v in System.ipairs(args) do
                t[k] = v
            end
            return type.c(unpack(t, 1, #args))
        end
    end
    return type.c(...)
end