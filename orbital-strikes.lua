require "functions"

function getOrCreateIndexForOrbital(entity)
	if not global.egcombat.orbital_indices[entity.unit_number] then
		--game.print("Calculating")
		local flag = false
		local entities = {}
		for _,entry in pairs(global.egcombat.orbital_indices) do
			if entry.entity.valid then
				table.insert(entities, entry.entity)
			else
				flag = true
			end
		end
		if flag then
			--game.print("Rebuilding list.")
			for i = 1,#entities do
				local val = entities[i]
				local entry2 = {index=i-1, entity=val}
				global.egcombat.orbital_indices[val.unit_number] = entry2
				--game.print("Reassigning " .. entry2.index .. " to " .. val.unit_number)
			end
		end
		--game.print("Assigning " .. #entities)
		local entry = {index=#entities, entity=entity}
		global.egcombat.orbital_indices[entity.unit_number] = entry
	end
	--game.print("Returning " .. global.egcombat.orbital_indices[entity.unit_number].index)
	return global.egcombat.orbital_indices[entity.unit_number].index
end

function scheduleOrbitalStrike(placer, inv, target)
	--inv.insert({name="orbital-manual-target", count=1})
	if not global.egcombat.scheduled_orbital then
		global.egcombat.scheduled_orbital = {}
	end
	if placer.force.get_item_launched("destroyer-satellite") > 0 and placer.force.is_chunk_charted(placer.surface, {math.floor(target.x/32), math.floor(target.y/32)}) and #placer.surface.find_entities_filtered({name="orbital-manual-target-secondary", area={{target.x-10, target.y-10},{target.x+10, target.y+10}}}) == 0 then
		local entity = placer.surface.create_entity({name="orbital-manual-target-secondary", position=target, force=placer.force})
		local loc = placer.surface.create_entity({name="orbital-manual-target-secondary", position=target, force=placer.force}) --just for location
		local fx = placer.surface.create_entity{name = "orbital-manual-target-effect", position=target}
		table.insert(global.egcombat.scheduled_orbital, {location = loc, next = entity, effect=fx, delay = 180, shots = 0})
		for _,player in pairs (game.connected_players) do
			player.add_custom_alert(entity, {type = "item", name = "orbital-manual-target"}, {"orbital-strike-incoming"}, true)
		end
		--game.print("Scheduling strike")
	else
		--target.destroy()
	end
end

function tickOrbitalStrikeSchedule()
	if global.egcombat.scheduled_orbital then
		for i=#global.egcombat.scheduled_orbital,1,-1 do
			local entry = global.egcombat.scheduled_orbital[i]
			entry.delay = entry.delay-1
			--game.print("Ticking strike @ " .. entry.location.position.x .. " , " .. entry.location.position.y .. " , tick = " .. entry.delay)
			if entry.delay == 0 then
				entry.shots = entry.shots+1
				fireOrbitalWeaponManually(entry.next)
				--game.print("Firing")
				local loc = entry.location.position
				if entry.shots < 10 and (math.random() < 0.4 or #entry.location.surface.find_entities_filtered({area = {{loc.x-24, loc.y-24}, {loc.x+24, loc.y+24}}, force=game.forces.enemy}) > 0) then
					entry.delay = math.random(5, 30)
					entry.next = entry.location.surface.create_entity({name="orbital-manual-target-secondary", position={loc.x+math.random(-10, 10), loc.y+math.random(-10, 10)}, force=entry.location.force})
				else
					table.remove(global.egcombat.scheduled_orbital, i)
					entry.location.destroy()
					entry.effect.destroy()
				end
			end
		end
	end
end

function fireOrbitalWeaponManually(target)
	local surface = target.surface
	local pos = target.position--player.selected and player.selected.position or ??
	surface.create_entity({name = "orbital-bombardment-firing-sound", position = pos, force = game.forces.neutral})
	surface.create_entity({name = "orbital-bombardment-explosion", position = pos, force = game.forces.neutral})
	surface.create_entity({name = "orbital-bombardment-crater", position = pos, force = game.forces.neutral})
	local entities = surface.find_entities_filtered({area = {{target.position.x-32, target.position.y-32}, {target.position.x+32, target.position.y+32}}})
	for _,entity in pairs(entities) do
		if entity.valid and entity.health and entity.health > 0 and game.entity_prototypes[entity.name].selectable_in_game then
			if getDistance(entity, target) <= 35 then
				if entity.type ~= "tree" and (entity.type == "player" or entity.type == "logistic-robot" or entity.type == "construction-robot" or (entity.force ~= target.force and (not target.force.get_cease_fire(entity.force)))) then
					if entity.type == "unit" or entity.type == "unit-spawner" then
						entity.surface.create_entity({name="blood-explosion-small", position=entity.position, force=entity.force})
					else
						entity.surface.create_entity({name="explosion", position=entity.position, force=entity.force})
					end
					entity.die()
				else
					entity.damage(entity.health*(0.8+math.random()*0.15), target.force, "explosion")
				end
			end
		end
	end
	target.destroy()
	for _,player in pairs (game.connected_players) do
		surface.create_entity{name = "orbital-manual-target-sound-1", position = player.position}
		surface.create_entity{name = "orbital-manual-target-sound-2", position = player.position}
	end
end

function fireOrbitalWeapon(force, entity)
	local surface = entity.surface
	local tries = 0
	local scanned = false
	while tries < 40 and not scanned do
		tries = tries+1
		local pos = {x=math.random(-40, 40), y=math.random(-40, 40)}--event.chunk_position
		pos.x = pos.x+16*math.floor(entity.position.x/32/16) --divide world into 16x16 chunk regions
		pos.y = pos.y+16*math.floor(entity.position.y/32/16)
		--game.print("Trying " .. pos.x .. "," .. pos.y .. " : " .. (force.is_chunk_charted(surface, pos) and "succeed" or "fail"))
		if force.is_chunk_charted(surface, pos) then
			scanned = true
			--destroy spawners in area, send spawn + some to attack
			--game.print(pos.x .. " , " .. pos.y)
			pos.x = pos.x*32
			pos.y = pos.y*32
			local r = 2
			local area = {{pos.x-r, pos.y-r}, {pos.x+32+r, pos.y+32+r}}
			local enemies = surface.find_entities_filtered({type = "unit-spawner", area = area, force = game.forces.enemy})
			local count = #enemies
			--game.print("Checking " .. pos.x/32 .. "," .. pos.y/32 .. " : " .. count)
			if count > 0 then
				for _,spawner in pairs(enemies) do						
					surface.create_entity({name = "orbital-bombardment-explosion", position = spawner.position, force = game.forces.neutral})
					surface.create_entity({name = "orbital-bombardment-crater", position = spawner.position, force = game.forces.neutral})
					
					spawner.die() --not destroy; use this so have destroyed spawners, drops, evo factor, NauvisDay spawns, etc
				end
				entity.energy = 0 --drain all power for a "shot"
				
				--[[
				for _,deadspawner in pairs(surface.find_entities_filtered({type = "corpse", area = area})) do
					deadspawner.
				end
				--]]
				
				surface.create_entity({name = "orbital-bombardment-firing-sound", position = entity.position, force = game.forces.neutral})
				--particles, sounds, maybe spawn some fire? (concern about forest fires)
				--[[
				surface.create_entity({name = "orbital-bombardment-crater", position = {math.random(pos.x+8, pos.x+24), math.random(pos.y+8, pos.y+24)}, force = game.forces.neutral})
				for i = 0,4 do
					surface.create_entity({name = "orbital-bombardment-explosion", position = {math.random(pos.x, pos.x+32), math.random(pos.y, pos.y+32)}, force = game.forces.neutral})
				end
				--]]
				
				--Hope your base is well defended... >:)
				local retaliation = surface.create_unit_group({position={pos.x+16, pos.y+16}, force=game.forces.enemy})
				local biters = surface.find_entities_filtered({type = "unit", area = area, force = game.forces.enemy})
				for _,biter in pairs(biters) do
					retaliation.add_member(biter)
				end
				local evo = game.forces.enemy.evolution_factor+math.random()*0.25
				local size = (1+((count-1)/2))*(10+math.ceil(15*evo))*(0.8+math.random()*0.7)
				while #retaliation.members < size do
					local biter = "small-biter"
					if evo >= 0.35 and math.random() < 0.5 then
						biter = "medium-biter"
					end
					if evo >= 0.6 and math.random() < 0.4 then
						biter = "big-biter"
					end
					if evo >= 0.9 and math.random() < 0.3 then
						biter = "behemoth-biter"
					end
					local spawn = surface.create_entity({name = biter, position = {math.random(pos.x, pos.x+32), math.random(pos.y, pos.y+32)}, force = game.forces.enemy})
					retaliation.add_member(spawn)
				end
				retaliation.set_command({type = defines.command.attack, target = entity, distraction = defines.distraction.none})
				
				surface.pollute({pos.x+16, pos.y+16}, 5000)
				local rs = 16
				force.chart(surface, {{pos.x-rs, pos.y-rs}, {pos.x+31+rs, pos.y+31+rs}})
			end
		end
	end
end