require "config"
require "constants"
require "functions"

require "__DragonIndustries__.tech"
require "__DragonIndustries__.items"
require "__DragonIndustries__.registration"

local MAKE_ITEMS = true--false

local baseturrets = {}
baseturrets = util.table.deepcopy(data.raw["ammo-turret"])
for _,v in pairs(data.raw["electric-turret"]) do 
	table.insert(baseturrets, v)
end
for _,v in pairs(data.raw["fluid-turret"]) do 
	table.insert(baseturrets, v)
end

local function isUnsafeModdedTurret(name)
	if (name == "at_CR_b" or name == "at_CR_s1" or name == "at_CR_s2" or name == "at_A1_b" or name == "at_A1_b" or name == "at_A2_b") then
		return true
	end
	return false
end

local function shouldCreateRangeTurret(base)
	if isTechnicalTurret(base.name) then return false end
	if isUnsafeModdedTurret(base.name) then return false end
	if string.find(base.name, "rangeboost") then return false end
	if base.type == "artillery-turret" or base.type == "artillery-wagon" then return false end
	return base.name ~= "last-stand-turret" and (not string.find(base.name, "shield-dome", 1, true)) and base.minable and base.minable.result --skip technicals
end

local turrets = {}
local items = {}

local function createRangeTurret(base, i)
	local turret = util.table.deepcopy(base)
	turret.name = turret.name .. "-rangeboost-" .. i
	table.insert(turret.flags, "hidden")
	turret.localised_name = {"turrets.upgrade", {"entity-name." .. base.name}, i}
	turret.attack_parameters.range = turret.attack_parameters.range+TURRET_RANGE_BOOST_SUMS[i]
	if turret.attack_parameters.type == "beam" and turret.attack_parameters.ammo_type then
		turret.attack_parameters.ammo_type.action.action_delivery.max_length = turret.attack_parameters.range
	end
	--[[
	if base.name == "shockwave-turret" then
		turret.attack_parameters.range = base.attack_parameters.range+math.ceil(TURRET_RANGE_BOOST_SUMS[i]/2)
	end
	--]]
	turret.hidden = true
	if not turret.flags then turret.flags = {} end
	table.insert(turret.flags, "hidden")
	--table.insert(turret.flags, "hide-from-bonus-gui")
	turret.order = "z"
	turret.placeable_by = {item=base.minable.result, count = 1}
	if MAKE_ITEMS then
		--turret.minable.result = turret.name can work without
	end
	--log("Adding ranged L" .. i .. " for " .. base.name .. ", range = R+" .. TURRET_RANGE_BOOST_SUMS[i])
	table.insert(turrets, turret)
				
	if MAKE_ITEMS then
		local baseitem = getItemByName(base.minable.result)
		if baseitem then
			local item = util.table.deepcopy(baseitem)
			item.name = turret.name
			if not item.flags then item.flags = {} end
			table.insert(item.flags, "hidden")
			table.insert(item.flags, "hide-from-bonus-gui")
			item.localised_name = base.localised_name--turret.localised_name
			item.order = "z"
			item.place_result = turret.name
			item.hidden = true
			--log("Adding ranged L" .. i .. " for " .. base.name .. ", range = R+" .. TURRET_RANGE_BOOST_SUMS[i])
			table.insert(items, item)
		else
			log("Could not create range boost version of turret with no item: " .. base.type .. " / " .. base.name)
		end
	end
end

for i = 1,#TURRET_RANGE_BOOSTS do
	for _,base in pairs(baseturrets) do
		if shouldCreateRangeTurret(base) then
			local status,err = pcall(function() createRangeTurret(base, i) end)
			if not status then
				log("Encountered error trying to make range turret " .. base.type .. " / " .. base.name .. ": " .. serpent.block(err))
			end
		end
	end
end

registerObjectArray(turrets)

--[[
for _,base in pairs(baseturrets) do
	local turret = util.table.deepcopy(base)
	turret.name = base.name .. "-range-blueprint"
	turret.localised_name = base.localised_name
	turret.order = "z"
	log("Adding BP'ed clone for " .. base.name .. " > " .. turret.name)
	data:extend(
	{
		turret
	})
	
	data:extend({
		{
			type = "item",
			name = turret.name,
			localised_name = base.localised_name,
			icon = "__base__/graphics/icons/radar.png", --temp
			flags = {},
			subgroup = "defensive-structure",
			order = "z",
			place_result = turret.name,
			stack_size = 1
		}
	})
end
--]]

if MAKE_ITEMS then
	registerObjectArray(items)
end

for _,tech in pairs(data.raw.technology) do
	if tech.effects and not isCampaignOnlyTech(tech) then
		local effectsToAdd = {}
		for _,effect in pairs(tech.effects) do
			if effect.type == "turret-attack" and effect.turret_id then
				local base = data.raw["ammo-turret"][effect.turret_id]
				if not base then
					base = data.raw["fluid-turret"][effect.turret_id]
				end
				if not base then
					base = data.raw["electric-turret"][effect.turret_id]
				end
				if not base then
					base = data.raw["artillery-turret"][effect.turret_id]
				end
				if not base then
					base = data.raw["artillery-wagon"][effect.turret_id]
				end
				if not base then Config.error("Tech " .. tech.name .. " set to boost turret '" .. effect.turret_id .. "', which does not exist! This is a bug in that mod!") end
				if base then
					if shouldCreateRangeTurret(base) then
						for i=1,10 do
							local effectcp = table.deepcopy(effect)--{type="turret-attack", turret_id=base.name .. "-rangeboost-" .. i, modifier=effect.modifier}
							effectcp.turret_id = base.name .. "-rangeboost-" .. i
							effectcp.effect_key = {"modifier-description." .. effect.turret_id .. "-attack-bonus"}
							table.insert(effectsToAdd, effectcp)
						end
					end
				end
			end
		end
		for _,effect in pairs(effectsToAdd) do
			table.insert(tech.effects, effect)
		end
	end
end