windower.register_event('load',function ()
	toggleBox('show')
	showBox()
	--Mastery Tracking for the Eventide server, will be updating as more masteries are added to the game
end)

_addon.name = 'MasteryTracker'
_addon.author = 'Otamarai'
_addon.version = '0.1'
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
spellTable = require('SpellTable')

--Defaults
masteries = {}
thfSAFlag = false

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


--Load the player mastery data
masteryData_file = files.new('MasteryData.lua')
if masteryData_file:exists() then
else
	masteryData = {}
	masteryData_file:write('return ' .. T(masteryData):tovstring())
end
masteryData = require('MasteryData')


function loadMasteryData()
	local player = windower.ffxi.get_player()
	local job = player.main_job
	local name = player.name
	
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
end

loadMasteryData()

--Save the player mastery data
function saveMasteryData()
	local player = windower.ffxi.get_player()
	local job = player.main_job
	local name = player.name
	
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
	end
end)


--Find what happened to hopefully get some mastery information
windower.register_event('action', function(act)
	local player = windower.ffxi.get_player()
	local job = player.main_job
	if act.actor_id == player.id then
		--Auto attack masteries
		if act.category == 1 and (job == 'WAR' or job == 'MNK' or job == 'THF' or job == 'DRK' or job == 'SAM' or job == 'NIN' or job == 'DRG') then
			if masteries[1] ~= 'Complete' then
				masteries[1] = masteries[1] + act.targets[1].actions[1].param
				if masteries[1] >= tonumber(masteryTable[job][1].Goal) then
					masteries[1] = 'Complete'
				end
				saveMasteryData()
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
				saveMasteryData()
				showBox()
			end
		--Ranged attack masteries
		elseif act.category == 2 and (job == 'RNG' or job == 'COR') then
			if masteries[1] ~= 'Complete' then
				masteries[1] = masteries[1] + act.targets[1].actions[1].param
				if masteries[1] >= tonumber(masteryTable[job][1].Goal) then
					masteries[1] = 'Complete'
				end
				saveMasteryData()
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
					saveMasteryData()
					showBox()
				end
			--THF use SA
			elseif masteries[1] == 'Complete' and masteries[2] ~= 'Complete' and act.param == 44 then
				thfSAFlag = true
			end
		--Spell cast masteries
		elseif act.category == 4 and (job == 'WHM' or job == 'BLM' or job == 'RDM' or job == 'BLU' or job =='SMN' or job == 'BRD') then
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
								saveMasteryData()
								showBox()
							end
						end
					end
				end
			end
		end
	--Needs testing to get accurate blocked value data
	elseif act.targets[1] and act.targets[1].id and act.targets[1].id == player.id then
		if job == 'PLD' and act.targets[1].actions[1] and act.targets[1].actions[1].reaction == 12 then	--normally reaction = 4 here, will monitor if it's different per server
			local blockedDamage = act.targets[1].actions[1].param*((100-shieldBlockPercent())/100)
			blockedDamage = math.floor(blockedDamage+0.5)
			--This isn't perfect, being higher level can actually make the mobs do 0 damage, but it's as close as we're gonna get without actual pre-blocked damage values
			if blockedDamage == 0 and not isBuffActive(50) and not isBuffActive(37) then blockedDamage = 1 end
			windower.add_to_chat(7, 'Blocked: '..blockedDamage)
			windower.add_to_chat(7, 'Got hit for: '..act.targets[1].actions[1].param)
			masteries[1] = masteries[1] + blockedDamage
			saveMasteryData()
			showBox()
		end
	end
end)



--Load new job mastery data upon job change
windower.register_event('job change', function(mainjob_id, mainjob_level, subjob_id, subjob_level)
	loadMasteryData()
	showBox()
end)



--Populate the box
function showBox()
	local player = windower.ffxi.get_player()
	if not player then return end
	local job = player.main_job
	list = ''
	list = list..job..' Mastery Progression\\cr\n'
	for i = 1, 5 do
		if masteryTable[job] and masteryTable[job][i].Type then
			if masteries[i] == 'Complete' then
				list = list..'\\cs(0,255,0)Mastery '..i..': Complete!['..masteryTable[job][i].Bonus..']\\cr\n'
			else
				list = list..'\\cs(50,113,68)Mastery '..i..': '..masteries[i]..'\/'..masteryTable[job][i].Goal..' '..masteryTable[job][i].Type..'\\cr\n'
			end
		end
	end
	masteryInfo.value = list
	masteryInfo:update()
end



windower.register_event('addon command', function(...)
	local command = {...}
	--Manually set the masteries here for your current job if something happened to the tracking or you aren't starting from 0
	if command[1] == 'set' then
		if command[2] then
			if command[2] == 'm1' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[1] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'm2' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[2] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'm3' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[3] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'm4' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[4] = tonumber(command[3]) or 'Complete'
			elseif command[2] == 'm5' and command[3] and (command[3]:ucfirst() == 'Complete' or tonumber(command[3])) then
				masteries[5] = tonumber(command[3]) or 'Complete'
			end
		end
		showBox()
	elseif command[1] == 'help' then
		windower.add_to_chat(7, 'Commands:')
		windower.add_to_chat(7, 'mt set m1|m2|m3|m4|m5 # - sets the specified mastery to the number provided')
	elseif command[1]:lower() == 'show' or command[1]:lower() == 'hide' or command[1]:lower() == 'visible' or command[1]:lower() == 'toggle' then
		toggleBox(command[1])
	end
end)









