windower.register_event('load',function ()
	toggleBox('show')
	showBox()
	--Mastery Tracking for the Eventide server, will be updating as more masteries are added to the game
end)

_addon.name = 'MasteryTracker'
_addon.author = 'Otamarai'
_addon.version = '0.2'
_addon.commands = {'masterytracker','mt'}
require ('strings')
require ('logger')
extdata = require('extdata')
files = require ('files')
res = require('resources')
packets = require('packets')
config = require('config')
texts = require('texts')
files = require ('files')
masteryTable = require('MasteryTable')
materiaTable = require('MateriaTable')
spellTable = require('SpellTable')
wsInfo = require('Weaponskills')

--Defaults
masteries = {}
materia = {}
thfSAFlag = false
restStatus = false
restTimeHP = false
restTimeMP = false
healedTime = false

--Main text box
txt = {}
txt.pos = {}
txt.pos.x = 180
txt.pos.y = 600
txt.text = {}
txt.text.font = 'Arial'
txt.text.size = 10
txt.flags = {}
txt.flags.right = false
txt.padding = 5
txt.visible = true

settings = config.load(txt)
masteryInfo = texts.new('${value}', settings)


--Create the files to store the data if they don't already exist
masteryData_file = files.new('MasteryData.lua')
if not masteryData_file:exists() then
	masteryData = {}
	masteryData_file:write('return ' .. T(masteryData):tovstring())
end
masteryData = require('MasteryData')

materiaData_file = files.new('MateriaData.lua')
if not materiaData_file:exists() then
	materiaData = {}
	materiaData_file:write('return ' .. T(materiaData):tovstring())
end
materiaData = require('MateriaData')


--Load the player mastery or materia data
function loadData(dataType)
	local player = windower.ffxi.get_player()
	local job = player.main_job
	local name = player.name
	if not dataType then
		return
	elseif dataType == 'mastery' then
		if not masteryData[name] then
			masteryData[name] = {}
		end
		if not masteryData[name][job] then
			masteryData[name][job] = {}
		end
		for i = 1, 5 do
			if not masteryData[name][job][i] then
				masteryData[name][job][i] = 0
			end
			if masteryData and masteryData[name] and masteryData[name][job] and masteryData[name][job][i] then
				masteries[i] = masteryData[name][job][i]
			end
		end
	elseif dataType == 'materia' then
		if not materiaData[name] then
			materiaData[name] = {}
		end
		for i = 1, 4 do
			if not materia[i] then
				materia[i] = {}
			end
			if not materiaData[name][i] then
				materiaData[name][i] = {}
				for k = 1, #materiaTable[i] do
					materiaData[name][i][k] = 0
				end
			end
			for k = 1, #materiaTable[i] do
				materia[i][k] = materiaData[name][i][k]
			end
		end
	end
end

loadData('mastery')
loadData('materia')

--Save the player mastery or materia data
function saveData(dataType)
	local player = windower.ffxi.get_player()
	local job = player.main_job
	local name = player.name
	if not dataType then
		return
	elseif dataType == 'mastery' then
		if not masteryData[name] then
			masteryData[name] = {}
		end
		if not masteryData[name][job] then
			masteryData[name][job] = {}
		end
		for i = 1, 5 do
			if not masteryData[name][job][i] then
				masteryData[name][job][i] = {}
			end
			masteryData[name][job][i] = masteries[i]
		end
		masteryData_file:write('return ' .. T(masteryData):tovstring())
	elseif dataType == 'materia' then
		if not materiaData[name] then
			materiaData[name] = {}
		end
		for i = 1, 4 do
			if not materiaData[name][i] then
				materiaData[name][i] = {}
			end
			for k = 1, #materiaTable[i] do
				materiaData[name][i][k] = materia[i][k]
			end
		end
		materiaData_file:write('return ' .. T(materiaData):tovstring())
	end
end

--Toggle the box visibility
function toggleBox(j)
	if j and j == 'show' then
		masteryInfo:show()
	elseif j and j == 'hide' then
		masteryInfo:hide()
	else
		if texts.visible(masteryInfo) then
			masteryInfo:hide()
		else
			masteryInfo:show()
		end
	end
	masteryInfo:update()
end


--Check if a buff is active, by ID
function isBuffActive(id)
	local self = windower.ffxi.get_player()
	for k,v in pairs(self.buffs) do
		if (v == id) then
			return true
		end	
	end
	return false
end

--Return the equipped item in a slot
function getEquippedItem(slotName)
	local inventory = windower.ffxi.get_items()
	local equipment = inventory['equipment'];
	local itemID = windower.ffxi.get_items(equipment[string.format('%s_bag', slotName)], equipment[slotName]).id
	--return res.items:with('id', itemID).en
	return itemID
end


--Find and calculate shield block damage reduction percent
function shieldBlockPercent()
	--Find the shield size
	local shieldSize = res.items[getEquippedItem('sub')].shield_size
	if not shieldSize then return end
	local shieldSizeReduction = {[1]=20,[2]=40,[3]=50,[4]=65,[5]=55}
	local shieldDefense = res.item_descriptions[getEquippedItem('sub')].en
	--Pull the defense value from the description of the shield
	shieldDefense = tonumber(string.match(shieldDefense, "%d+"))
	local percentBlocked = shieldSizeReduction[shieldSize] + (shieldDefense / 2)
	return percentBlocked
end

--Check for buffs
windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
	--Character update
	if id == 0x037 then
		--Sneak attack buff check
		if not isBuffActive(65) and thfSAFlag then
			thfSAFlag = false
		elseif isBuffActive(65) and not thfSAFlag then
			thfSAFlag = true
		end
		local packets = packets.parse('incoming', data)
		if packets['Status'] == 33 then
			if not restStatus then
				restTimeHP = os.clock()
				restTimeMP = os.clock()
			end
			restStatus = true
		elseif packets['Status'] ~= 33 then
			restStatus = false
			restTimeHP = false
			restTimeMP = false
		end
	end
end)

windower.register_event('hp change', function(newHP, oldHP)
	local player = windower.ffxi.get_player()
	local hpChange = newHP - oldHP
	if hpChange >= 1 and restStatus then
		local autoRegen = false
		for k, v in pairs(windower.ffxi.get_abilities().job_traits) do
			if v == 9 then
				autoRegen = true
			end
		end
		if autoRegen and (player.vitals.max_hp - oldHP > 1) and hpChange == 1 then return end
		if (isBuffActive(42) or isBuffActive(539)) and (player.vitals.max_hp - oldHP > 5) and hpChange == 5 then return end
		if (isBuffActive(42) or isBuffActive(539)) and (player.vitals.max_hp - oldHP) >= 5 then
			hpChange = hpChange - 5
		end
		if autoRegen then
			hpChange = hpChange - 1
		end
		if healedTime and (math.abs(os.clock() - healedTime) <= 0.5) then return end
		if ((os.clock() - restTimeHP) >= 8 and (os.clock() - restTimeHP) <= 13) or ((os.clock() - restTimeHP) >= 19 and (os.clock() - restTimeHP) <= 23) then
			restTimeHP = os.clock()
			if hpChange >= 1 then
				materia[1][1] = materia[1][1] + hpChange
				if materia[1][1] >= tonumber(materiaTable[1][1].Goal) then
					materia[1][1] = 'Complete'
				end
				saveData('materia')
				showBox()
			end
		end
	end
end)

--Calculate the mp change while resting. This is not perfect, sometimes you will get a tic of refresh while resting mp back in the same go, but it's a decent estimate.
windower.register_event('mp change', function(newMP, oldMP)
	local player = windower.ffxi.get_player()
	local mpChange = newMP - oldMP
	if mpChange >= 1 and restStatus then
		local autoRefresh = false
		for k, v in pairs(windower.ffxi.get_abilities().job_traits) do
			if v == 10 then
				autoRefresh = true
			end
		end
		if autoRefresh and (player.vitals.max_mp - oldMP > 1) and mpChange == 1 then return end
		--Check for ballad or refresh, though can only check for one instance of ballad with this method
		if (isBuffActive(43) or isBuffActive(541) or isBuffActive(196)) and (player.vitals.max_mp - oldMP > 4) and mpChange <= 4 then return end
		
		
		if (isBuffActive(43) or isBuffActive(541)) and (player.vitals.max_mp - oldMP) >= 3 then
			mpChange = mpChange - 3
		end
		if (isBuffActive(196)) and (player.vitals.max_mp - oldMP) >= 1 then
			mpChange = mpChange - 1
		end
		if autoRefresh then
			mpChange = mpChange - 1
		end
		if ((os.clock() - restTimeMP) >= 8 and (os.clock() - restTimeMP) <= 13) or ((os.clock() - restTimeMP) >= 19 and (os.clock() - restTimeMP) <= 23) then
			restTimeMP = os.clock()
			if mpChange >= 1 then
				materia[1][2] = materia[1][2] + mpChange
				if materia[1][2] >= tonumber(materiaTable[1][2].Goal) then
					materia[1][2] = 'Complete'
				end
				saveData('materia')
				showBox()
			end
		end
	end
end)


--Find what happened to hopefully get some mastery and materia information
windower.register_event('action', function(act)
	local player = windower.ffxi.get_player()
	local job = player.main_job
	if act.actor_id == player.id then
		--Auto attack masteries
		if act.category == 1 and (job == 'WAR' or job == 'MNK' or job == 'THF' or job == 'DRK' or job == 'SAM' or job == 'NIN' or job == 'DRG') then
			if masteries[1] ~= 'Complete' then
				for i = 1, #act.targets[1].actions do
					masteries[1] = masteries[1] + act.targets[1].actions[i].param
				end
				if masteries[1] >= tonumber(masteryTable[job][1].Goal) then
					masteries[1] = 'Complete'
				end
				saveData('mastery')
				showBox()
			--THF Mastery 2
			elseif masteries[1] == 'Complete' and masteries[2] ~= 'Complete' and job == 'THF' then
				if thfSAFlag and act.targets[1].actions[1].message == 67 then
					masteries[2] = masteries[2] + 1
					thfSAFlag = false
					if masteries[2] >= tonumber(masteryTable[job][2].Goal) then
						masteries[2] = 'Complete'
					end
				elseif thfSAFlag and (act.targets[1].actions[1].message == 1 or act.targets[1].actions[1].message == 15) then
					thfSAFlag = false
				end
				saveData('mastery')
				showBox()
			end
		--Ranged attack masteries
		elseif act.category == 2 and (job == 'RNG' or job == 'COR') then
			if masteries[1] ~= 'Complete' then
				masteries[1] = masteries[1] + act.targets[1].actions[1].param
				if masteries[1] >= tonumber(masteryTable[job][1].Goal) then
					masteries[1] = 'Complete'
				end
				saveData('mastery')
				showBox()
			end
		--JA masteries, just BST and THF for now
		elseif (act.category == 6 or act.category == 14) and (job == 'THF' or job == 'BST') then
			if masteries[1] ~= 'Complete' then
			--BST Charm/jugs
				if job == 'BST' and (act.param == 52 or act.param == 85 or act.param == 387) then
					if act.param == 52 then
						if act.targets[1].actions[1].message ~= 137 and act.targets[1].actions[1].message == 100 then
							masteries[1] = masteries[1] + 1
						end
					else
						masteries[1] = masteries[1] + 1
					end
					saveData('mastery')
					showBox()
				end
			--THF use SA
			elseif masteries[1] == 'Complete' and masteries[2] ~= 'Complete' and act.param == 44 then
				thfSAFlag = true
			end
		--Weaponskill materia
		elseif act.category == 3 then
			local wsID = act.param
			for i = 1, #wsInfo[wsID].modifier do
				local materiaID = materiaTable[1]:with('Bonus', wsInfo[wsID].modifier[i]..'+1')
				if materiaID then
					materia[1][materiaID.id] = materia[1][materiaID.id] + 1
					if materia[1][materiaID.id] >= tonumber(materiaTable[1][materiaID.id].Goal) then
						materia[1][materiaID.id] = 'Complete'
					end
					saveData('materia')
					showBox()
				end
			end
			
		
		elseif act.category == 4 then
			--Nukes and cures for materia tier 1
			if materia[1][9] ~= 'Complete' and spellTable['INT']:contains(tostring(act.param)) then
				materia[1][9] = materia[1][9] + 0.1
				if materia[1][9] >= tonumber(materiaTable[1][9].Goal) then
					materia[1][9] = 'Complete'
				end
				saveData('materia')
				showBox()
			elseif materia[1][8] ~= 'Complete' and spellTable['MND']:contains(tostring(act.param)) then
				local realHealCheck = false
				for i = 1, #act.targets do
					if not windower.ffxi.get_mob_by_id(act.targets[i].id).is_npc and act.targets[i].actions[1].param >= 1 then
						realHealCheck = true
					end
				end
				if realHealCheck then
					materia[1][8] = materia[1][8] + 0.1
					if materia[1][8] >= tonumber(materiaTable[1][8].Goal) then
						materia[1][8] = 'Complete'
					end
					saveData('materia')
					showBox()
				end
			end
			--Spell cast masteries
			if job == 'WHM' or job == 'BLM' or job == 'RDM' or job == 'BLU' or job =='SMN' or job == 'BRD' then
				if masteries[1] ~= 'Complete' then
					--Too lazy to sort and add all the physical blu spells
					if job == 'BLU' or (job ~= 'BLU' and spellTable[job]:contains(tostring(act.param))) then
						if job ~= 'WHM' or (job == 'WHM' and not windower.ffxi.get_mob_by_id(act.targets[1].id).is_npc) then
							if act.targets[1].actions[1].message ~= 75 and act.targets[1].actions[1].message ~= 85 and act.targets[1].actions[1].message ~= 284 and act.targets[1].actions[1].message ~= 653 and act.targets[1].actions[1].message ~= 654 and act.targets[1].actions[1].message ~= 655 and act.targets[1].actions[1].message ~= 656 then
								--Check for physical blu spells here
								if job ~= 'BLU' or (job == 'BLU' and res.jobs[16].element == 15 and res.jobs[16].targets == 32) then
									if job == 'RDM' or job == 'SMN' or job == 'BRD' then
										masteries[1] = masteries[1] + 1
									else
										masteries[1] = masteries[1] + act.targets[1].actions[1].param
									end
									if masteries[1] >= tonumber(masteryTable[job][1].Goal) then
										masteries[1] = 'Complete'
									end
									saveData('mastery')
									showBox()
								end
							end
						end
					end
				end
			end
		end
	--Needs testing to get accurate blocked value data
	elseif act.targets[1] and act.targets[1].id and act.targets[1].id == player.id then
		if job == 'PLD' then
			for i = 1, #act.targets[1].actions do
				if act.targets[1].actions[i] and act.targets[1].actions[i].reaction == 12 then	--normally reaction = 4 here, will monitor if it's different per server
					local blockedDamage = act.targets[1].actions[i].param*((100-shieldBlockPercent())/100)
					blockedDamage = math.floor(blockedDamage+0.5)
					--This isn't perfect, being higher level can actually make the mobs do 0 damage, but it's as close as we're gonna get without actual pre-blocked damage values
					if blockedDamage == 0 and not isBuffActive(50) and not isBuffActive(37) then blockedDamage = 1 end
					masteries[1] = masteries[1] + blockedDamage
					saveData('mastery')
					showBox()
				end
			end
		end
		if act.category == 1 then
			--Checking for damage taken to update DEF+1 materia
			if materia[1][3] ~= 'Complete' then
				for i = 1, #act.targets[1].actions do
					materia[1][3] = materia[1][3] + act.targets[1].actions[i].param
				end
				if materia[1][3] >= tonumber(materiaTable[1][3].Goal) then
					materia[1][3] = 'Complete'
				end
				saveData('materia')
				showBox()
			end
		--Checking for heals to try and filter them out against rested healing tics
		elseif act.category == 4 then
			if spellTable['MND']:contains(tostring(act.param)) then
				healedTime = os.clock()
			end
		end
	end
end)






--Load new job mastery data upon job change
windower.register_event('job change', function(mainjob_id, mainjob_level, subjob_id, subjob_level)
	loadData('mastery')
	showBox()
end)


Headers = T{
	['Mastery'] = true,
	['Materia'] = true,
	['Tier1'] = true,
	['Tier2'] = false,
	['Tier3'] = false,
	['Tier4'] = false,
}



--Populate the box
function showBox()
	local player = windower.ffxi.get_player()
	if not player then return end
	local job = player.main_job
	list = ''
	if Headers['Mastery'] then
		list = list..job..' Mastery Progression\\cs(35,64,232) ▼\\cr\n'
		for i = 1, 5 do
			if masteryTable[job] and masteryTable[job][i].Type then
				if masteries[i] == 'Complete' then
					list = list..'\\cs(0,255,0)Mastery '..i..': Complete!['..masteryTable[job][i].Bonus..']\\cr\n'
				else
					list = list..'\\cs(50,113,68)Mastery '..i..': '..masteries[i]..'\/'..masteryTable[job][i].Goal..' '..masteryTable[job][i].Type..'\\cr\n'
				end
			end
		end
	else
		list = list..job..' Mastery Progression\\cs(35,64,232) ►\\cr\n'
	end
	list = list..'\n'
	if Headers['Materia'] then
		list = list..'Materia Progression\\cs(35,64,232) ▼\\cr\n'
		for i = 1, 4 do
			if materiaTable[i][1].Req then
				if Headers['Tier'..i] then
					list = list..'Tier '..i..' Materia\\cs(42,40,79) ▼\\cr\n'
					for k = 1, #materiaTable[i] do
						if materiaTable[i][k] then
							if materia[i][k] == 'Complete' then
								list = list..'\\cs(0,255,0)'..materiaTable[i][k].Bonus..': Complete!\\cr\n'
							else
								list = list..'\\cs(50,113,68)'..materiaTable[i][k].Bonus..': '..materia[i][k]..'\/'..materiaTable[i][k].Goal..' '..materiaTable[i][k].Req..'\\cr\n'
							end
						end
					end
				else
					list = list..'Tier '..i..' Materia\\cs(42,40,79) ►\\cr\n'
				end
			end
		end
	else
		list = list..'Materia Progression\\cs(35,64,232) ►\\cr\n'
	end
	masteryInfo.value = list
	masteryInfo:update()
end



windower.register_event('addon command', function(...)
	local command = {...}
	--Manually set the masteries or materia here for your current job if something happened to the tracking or you aren't starting from 0
	if command[1] == 'set' then
		if command[2] then
			if command[2] == 'mas1' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[1] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'mas2' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[2] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'mas3' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[3] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'mas4' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[4] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'mas5' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[5] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'mat' and command[3] and command[4] and command[5] then
				local com3 = tonumber(command[3])
				local com4 = tonumber(command[4])
				if materia[com3] and materia[com3][com4] and (command[5]:ucfirst() == 'Complete' or tonumber(command[5])) then
					materia[com3][com4] = tonumber(command[5]) or 'Complete'
				end
			end
		end
		showBox()
	elseif command[1] == 'header' and command[2] then
		Headers[command[2]] = not Headers[command[2]]
		showBox()
	elseif command[1] == 'help' then
		windower.add_to_chat(7, 'Commands:')
		windower.add_to_chat(7, 'mt set mas1|mas2|mas3|mas4|mas5 # - sets the specified mastery to the number provided')
		windower.add_to_chat(7, 'mt set mat [tier] [materia#] # - sets the specified materia to the number provided. Example: "mt set mat 1 2 2000"')
		windower.add_to_chat(7, 'mt show|hide|visible|toggle - shows/hides or toggles visibility on the ui box')
	elseif command[1]:lower() == 'show' or command[1]:lower() == 'hide' or command[1]:lower() == 'visible' or command[1]:lower() == 'toggle' then
		toggleBox(command[1])
	end
end)



--Mouse detection for the box
windower.register_event('mouse', function(type, x, y, delta, blocked)
	local player = windower.ffxi.get_player()
	local mx, my = texts.extents(masteryInfo)
	local buttonLines = masteryInfo:text():count('\n')
	local hx = (x - settings.pos.x)
	local hy = (y - settings.pos.y)
	local location = {}
	location.offset = my / buttonLines
	location[1] = {}
	location[1].ya = 1
	location[1].yb = location.offset
	for i = 2, buttonLines do
		location[i] = {}
		location[i].ya = location[i - 1].yb
		location[i].yb = location[i - 1].yb + location.offset
	end
	--On left click
	if type == 2 then
		if masteryInfo:hover(x, y) and masteryInfo:visible() then
			for i, v in ipairs(location) do
				local n = 1
				local switchb = {}
				switchb[n] = 'Mastery'
				n = n + 1
				if Headers['Mastery'] then
					for k = 1, 5 do
						if masteryTable[player.main_job] and masteryTable[player.main_job][k].Type then
							n = n + 1
						end
					end
				end
				n = n + 1
				switchb[n] = 'Materia'
				if Headers['Materia'] then
					for j = 1, 4 do
						if materiaTable[j][1].Req then
							n = n + 1
							switchb[n] = 'Tier'..j
							if Headers['Tier'..j] then
								for k = 1, #materiaTable[j] do
									if materiaTable[j][k] then
										n = n + 1
									end
								end
							end
						end
					end
				end
				if hy > location[i].ya and hy < location[i].yb then
					if switchb[i] and switchb[i] ~= "" then
						windower.send_command("mt header "..switchb[i])
					end
				end
			end
		end
	end
end)





