require("MarLibrary.Events")

if getActivatedMods():contains("\\MoodleFramework") == true then
	require "MF_ISMoodle" --Moodle Framework requirement for moodle stuff
end

MarTraits = MarTraits or {}

-- TODO: add an increase spike of sneeze chance when rummaging through containers in a heavily "dusty" room
-- TODO: change dust calculation to be stronger based on how much relative dust in room compared to how many squares, rather than dust in all squares total?
-- TODO: add an absolute smidgen of an effect for dust allergies when you have obscenely dirty clothes, shouldn't be hard.

--Declare local scope variables
local baseSneezeCountdown = 150 -- Counter to reset to on sneeze
local sneezeTimeMultiplier = 1.0 -- Modified by traits like Prone to Illness
local allergyRate = 0.02 --Multiplier on how fast allergy moodles move up and down
local baseAllergyRecoveryRate = 0.4 -- How quickly allergies should recover per minute
local proportionalAllergyRecoveryRate = 10.0 -- At max allergy, the base rate is multiplied by this number to return to "normal"
local seasonDelta = 0.0 -- Tracks the effect of seasons outside of the season update.
local sneezeSoundRange = 30 --Default range
local sneezeSoundVolume = 30 --Default volume
local conspicuousMod = 0.3 --A percentage (0.0 - 1.0) for more or less range depending on traits
local sneezeMuteMod = 0.1 --Multiplier on range and volume when muted. In vanilla, this is full mute, or 0.0
local sneezeColdMod = 1.25 --Multiplier on range/volume if player has a cold also. 1.0 is default volume
local tissueUseChance = 100 --Modifier on the chance to use tissues last from sneezes. 0 - 100%.

local totalPollen = 0.0 -- Trackers for update functions
local totalDirt = 0.0 -- Trackers for update functions
local dustRoom = 0.0
local dustSquare = 0.0

local roomSquareSize = 0
local dustRoomMod = -0.15 --Amount to subtract from dust allergy moodle relative to ratio of dust in room to size of room.
local dustSquareMod = -3.0 --Amount to subtract from dust moodle per dust near player
local dustRoomRatio = 0

local treeSneezeCost = -20 --Amount to subtract from sneezeCountdown when in trees, also based off seasonal stuff, so set low by default
local rummageDustRoomRatioSpikeMod = -10 -- How much influence each 1 dust in the room has on sneeze when rummaging in it.
local rummageDustSquareSpikeMod = -5 -- How much influence each 1 dust the square you are on rummaging in every delta.

local player = nil
local validItemTypes = {} -- A list of valid body slots for pollen tracked items to exist in

local countChangeMoodleMax = 15 -- how much count change is needed for the moodle be maxed out.

local countGradualChange = 0.00
local countSpikeChange = 0.00 -- Used for instances where we want the count to go down alot, like walking through trees, seperates it from moodle.

local countSpikeMoodleActivateThreshold = -1
local countChangeGradualMoodleActivateThreshold = 2 -- how much count change is needed for the moodle to consider showing. 

MarTraits.allergiesMoodleActive = false
MarTraits.allergiesMoodleSavedValue = 0

local function allergicOnCreatePlayer(playerIndex, createdPlayer) --Load data on player creation
	player = createdPlayer

	-- That boy can SNEEZE!
	if player:HasTrait("ProneToIllness") then
		sneezeTimeMultiplier = sneezeTimeMultiplier * 0.75
	end

	if player:getModData().dictMarTraitsTrackedItems == nil then
		print("Adding item tracking to player")
		player:getModData().dictMarTraitsTrackedItems = {}
	else
		print("Item tracking already added.")
	end

	if player:HasTrait("Mar_DustAllergic") or player:HasTrait("Mar_SeasonAllergic") then

		if player:getModData().fMarTraitsSneezeCountdown == nil then
			print("Nil sneeze countdown, initializing")
			player:getModData().fMarTraitsSneezeCountdown = baseSneezeCountdown * sneezeTimeMultiplier
		end

		--With the Inconspicuous trait and base values of 30, sneezes match range and volume of vanilla.
		--With no trait, they are louder by about 30%. With Conspicuous, this is again louder.
		if player:HasTrait("Conspicuous") then
			sneezeSoundRange = sneezeSoundRange + (sneezeSoundRange * conspicuousMod)
			sneezeSoundVolume = sneezeSoundVolume + (sneezeSoundVolume * conspicuousMod)
		elseif player:HasTrait("Inconspicuous") then
			sneezeSoundRange = sneezeSoundRange - (sneezeSoundRange * conspicuousMod)
			sneezeSoundVolume = sneezeSoundVolume + (sneezeSoundVolume * conspicuousMod)
		end
		
		if player:HasTrait("Mar_DustAllergic") then
			if player:getModData().fMarTraitsDustAllergyLevel == nil then
				print("Nil allergy level, initializing")
				player:getModData().fMarTraitsDustAllergyLevel = 0
			end

			print("DustAllergic Trait Character Initialized")
		end

		if player:HasTrait("Mar_SeasonAllergic") then
			if player:getModData().fMarTraitsSeasonAllergyLevel == nil then
				print("Nil allergy level, initializing")
				player:getModData().fMarTraitsSeasonAllergyLevel = 0
			end

			print("SeasonAllergic Trait Character Initialized")
		end
	end
end
Events.OnCreatePlayer.Add(allergicOnCreatePlayer)

MarTraits.getItemPollen = function(item)
	return item:getModData().fMarTraitsPollenLevel
end

MarTraits.setItemPollen = function(item, amount)
	item:getModData().fMarTraitsPollenLevel = PZMath.clamp(amount,0,1)
end

MarTraits.addItemPollen = function(item, amount)
	if player == nil then 
		player = getPlayer()
	end

	local parts = item:getCoveredParts()
	local randIndex = ZombRand(0,item:getNbrOfCoveredParts())
	local selected = parts:get(randIndex)
	-- local player = getPlayer()

	-- Add dirt so player can clean it.
	-- TODO: Not ideal since this does not communicate HOW much pollen is on the clothes to the player at all, but the alternative is getting really dirty just by being in the wind.
	if not item:hasDirt() then
		player:addDirt(selected, 1, true)
	end

	--print("Typeof parts: ",type(parts))
	--print("Adding dirt to part: "..selected:getDisplayName())

	MarTraits.setItemPollen(item,amount + MarTraits.getItemPollen(item))
end

MarTraits.addTrackedItemType = function(strType)
	table.insert(validItemTypes,strType)
end

MarTraits.isValidItemType = function(item)
	--print(item:getName().." is worn on "..item:getBodyLocation())
	for i, validType in pairs(validItemTypes) do
		if item:getBodyLocation() == validType then return true end
	end
	return false
end

MarTraits.trackItem = function (player, item)
	if player:getModData().dictMarTraitsTrackedItems[item:getID()] == nil then
		player:getModData().dictMarTraitsTrackedItems[item:getID()] = item
		print("Tracking item "..item:getID())
	end
end

MarTraits.untrackItem = function(player, item)
	player:getModData().dictMarTraitsTrackedItems[item:getID()] = nil
end

MarTraits.updateTrackedItems = function()
	if player == nil then 
		player = getPlayer()
	end
	--print("Updating Tracked Items")

	if player:getModData().dictMarTraitsTrackedItems == nil or player:getModData().dictMarTraitsTrackedItems == {} then
		return
	end

	for ID, item in pairs(player:getModData().dictMarTraitsTrackedItems) do
		local pollen = MarTraits.getItemPollen(item)
		--print("Item "..item:getName().." has pollenLevel "..pollen)

		local wet = item:getWetness()
		if wet ~= nil and wet > 0 then
			local newMax = PZMath.max(100 - (wet * 2), 0)/100.0
			--print("Item is wet: "..wet.." , new max pollen "..newMax)
			MarTraits.setItemPollen(item, PZMath.clampFloat(pollen, 0.0, newMax))
		end

		if MarTraits.getItemPollen(item) <= 0 then
			--print("Item "..item:getName().." is clean, remove from tracking!")
			MarTraits.untrackItem(player,item)	
		end
	end
end
Events.EveryTenMinutes.Add(MarTraits.updateTrackedItems)

--A list of item slots we can track pollen on.
MarTraits.addTrackedItemType("Hat")
MarTraits.addTrackedItemType("TorsoExtraVest")
MarTraits.addTrackedItemType("Jacket")
MarTraits.addTrackedItemType("Sweater")
MarTraits.addTrackedItemType("Dress")
MarTraits.addTrackedItemType("Shirt")
MarTraits.addTrackedItemType("Tshirt")
MarTraits.addTrackedItemType("TankTop")
MarTraits.addTrackedItemType("Pants")
--MarTraits.addTrackedItemType("Mask") --Don't track mask, just look for the equip slot to reduce effect.

MarTraits.resetSneezeCountdown = function()
	local fitChance = 20
	local new_countdown = baseSneezeCountdown * sneezeTimeMultiplier * (ZombRand(50,100) / 100)

	local moodle = nil
	if MarTraits.moodleFrameworkActive then
		moodle = MF.getMoodle("Allergies", player:getPlayerNum())
	end
	if moodle then
		fitChance = PZMath.lerp(100, 10, moodle:getValue())
		print("Fit Chance : ",fitChance)
	--Reset much smaller if we roll low!
	end
	if ZombRand(100) > fitChance then
		MarTraits.setSneezeCountdown(player, new_countdown)
	else
		print("Fit Trigger!")
		MarTraits.setSneezeCountdown(player, new_countdown * 0.1)
	end
end

MarTraits.setSneezeCountdown = function(player, newLevel)
	player:getModData().fMarTraitsSneezeCountdown = PZMath.clamp(newLevel,-1,baseSneezeCountdown*sneezeTimeMultiplier)
	return newLevel
end

-- Was having some errors with these getters on intializer not working on second player create? so added the "or"'s probably not performant...
MarTraits.getSneezeCountdown = function(player)
	return player:getModData().fMarTraitsSneezeCountdown
end

MarTraits.setSeasonAllergyLevel = function(player,newLevel)
	-- Clamped so "Good" versions don't appear
	player:getModData().fMarTraitsSeasonAllergyLevel = PZMath.clamp(newLevel,0,1)
	return newLevel
end

MarTraits.getSeasonAllergyLevel = function(player)
	return player:getModData().fMarTraitsSeasonAllergyLevel
end

MarTraits.setDustAllergyLevel = function(player,newLevel)
	-- Clamped so "Good" versions don't appear
	player:getModData().fMarTraitsDustAllergyLevel = PZMath.clamp(newLevel,0,1)
	return newLevel
end

MarTraits.getDustAllergyLevel = function(player)
	return player:getModData().fMarTraitsDustAllergyLevel
end

-- TODO: Add random selection of peak season, then change around it, fall, summer, etc.
MarTraits.allergicSeasonUpdate = function()
	local climate = getWorld():getClimateManager()
	local season = climate:getSeasonName()

	-- Like does lua have switch statements or what cuz?????
	if season == "Early Summer" then
		seasonDelta = 3.5
	elseif season == "Summer" then
		seasonDelta = 2.5
	elseif season == "Early Autumn" then
		seasonDelta = 2.0
	elseif season == "Autumn" then
		seasonDelta = 1.0
	elseif season == "Early Winter" then
		seasonDelta = 0.0
	elseif season == "Winter" then
		seasonDelta = 0.0
	elseif season == "Early Spring" then
		seasonDelta = 3.0
	elseif season == "Spring" then
		seasonDelta = 5.0 -- Tree Pollen Baybee May go CRAZY!
	end

	print("Season: "..season.." Effect: "..seasonDelta)

end
Events.EveryDays.Add(MarTraits.allergicSeasonUpdate)
Events.OnCreatePlayer.Add(MarTraits.allergicSeasonUpdate)

MarTraits.addClothesPollen = function(player,amount)
	if player == nil then 
		player = getPlayer()
	end

	local items = player:getWornItems()
	local size = items:size() - 1
	--print("Items: "..size)
	--print("CLOTHING UPDATE")
	for c=0,size do
		local item = items:getItemByIndex(c)
		if item:IsClothing() and MarTraits.isValidItemType(item) then
			MarTraits.addItemPollen(item,amount)
			MarTraits.trackItem(player,item)
		end
	end
end

MarTraits.clothesUpdated = function(player)
	if player == nil then 
		player = getPlayer()
	end

	if player == getPlayer() then
		local items = player:getWornItems()
		local size = items:size() - 1
		--print("Items: "..size)
		--print("CLOTHING UPDATE")
		for c=0,size do
			local item = items:getItemByIndex(c)
			if item:IsClothing() and MarTraits.isValidItemType(item) then
				--print(item:getName() .. " -- Equipped on " .. items:getLocation(item))
				if MarTraits.getItemPollen(item) == nil then
					MarTraits.setItemPollen(item,0)
					print("Added Pollen Tracking to item")
				elseif MarTraits.getItemPollen(item) > 0 then
					MarTraits.trackItem(player,item)
				end
			end
		end
	end
end
Events.OnClothingUpdated.Add(MarTraits.clothesUpdated)

MarTraits.updateClothesTotalPollen = function()
	if player == nil then 
		player = getPlayer()
	end

	-- local player = getPlayer()
	local items = player:getWornItems()
	local size = items:size() - 1
	totalPollen = 0

	for c=0,size do
		local item = items:getItemByIndex(c)
		--print(item:getName() .. items:getLocation(item))

		local pollen = MarTraits.getItemPollen(item)
		if pollen ~= nil then
			if items:getLocation(item) == "Pants" then
				totalPollen = totalPollen + (pollen * 0.25) --Smaller effect from pants
			else
				totalPollen = totalPollen + pollen
			end
		end
	end
end
Events.EveryTenMinutes.Add(MarTraits.updateClothesTotalPollen)

local dustSquareMax = 4
MarTraits.sumDustInSquare = function(gridSquare)
    if gridSquare == nil then return 0 end

    local squareObjects = gridSquare:getObjects()
    if squareObjects == nil then return 0 end

    local dustSum = 0

    --print("There are ",squareObjects:size()," objects in this square")

    for i=0,squareObjects:size()-1 do
        if dustSum >= dustSquareMax or i > 15 then --Sanity check, prevent huge returns or super long loops if somehow there are a lot of objects.
            break
        end

        local object = squareObjects:get(i);
        
        if object then
            local attachedsprite = object:getAttachedAnimSprite()
            
            if object:getTextureName() and luautils.stringStarts(object:getTextureName(), "overlay_grime") then
                -- Dirty Tile
                dustSum = dustSum + 1
                -- print("Dirty Texture")
            end
            
            if object:getOverlaySprite() and object:getOverlaySprite():getName() and luautils.stringStarts(object:getOverlaySprite():getName(), "overlay_grime") then
                -- Dirty Tile
                dustSum = dustSum + 1
                -- print("Dirty OverlaySprite")
            end

            if attachedsprite then
                for n=1,attachedsprite:size() do
                    local sprite = attachedsprite:get(n-1)
                    
                    if sprite and sprite:getParentSprite() and sprite:getParentSprite():getName() and luautils.stringStarts(sprite:getParentSprite():getName(), "overlay_grime") then
                        -- Dirty Tile
                        dustSum = dustSum + 1
                        -- print("Dirty AttachedSprite")
                    end
                end 
            end 
        end
    end

    return dustSum
end

local dustRoomMax = 30
MarTraits.allergyDustInRoom = function(player, roomDef)
	if player == nil then 
		player = getPlayer()
	end

    if not player:HasTrait("Mar_DustAllergic") or player:isAsleep() or player:isOutside() then
        dustRoom = 0
        return
    end

	-- If roomDef still = nil, then there is none.
    if roomDef == nil then 
        dustRoom = 0
        return 
    end
	
	local roomSquares = roomDef:getIsoRoom():getSquares()
	--print("--== Dust Room Debugger ==--")

	local dustSum = 0
	
    --print("There are ",roomSquares:size()," squares in this room.")

	roomSquareSize = roomSquares:size()

	-- If room is big enough, it uses radius around player instead of the total size of room.
    if roomSquares:size() > 50 then
		roomSquareSize = 50
        local x = player:getX()
        local y = player:getY()
        local z = player:getZ()

        local playerSquare = player:getSquare()

        for squareX = x-5, x+5 do
            if dustSum >= dustRoomMax then
                break
            end
            for squareY = y-5, y+5 do
                local square = getCell():getGridSquare(squareX,squareY,z)
				if square != nil then
                	if playerSquare:getRoomID() == square:getRoomID() then
                    	dustSum = dustSum + MarTraits.sumDustInSquare(square)
                	end
				end
            end
        end
    else
        for s=0, roomSquares:size()-1 do
            if dustSum >= dustRoomMax then
                break
            end
            dustSum = dustSum + MarTraits.sumDustInSquare(roomSquares:get(s))
        end
    end

    --print("Dust in Player Room: ",dustSum)

    dustRoom = PZMath.clamp(dustSum,0,dustRoomMax)
end
MarLibrary.Events.OnPlayerMoveRoom:Add("MarTraits.allergyDustInRoom", MarTraits.allergyDustInRoom)

-- Just runs the allegy dust room update every hour as niche check you have been standing in a cleaning room for awhile.
local function allergyDustInRoomHourlyUpdate()
	if player == nil then 
		player = getPlayer()
	end

	local roomDef = player:getCurrentRoomDef()
	MarTraits.allergyDustInRoom(player, roomDef)
end
Events.EveryHours.Add(allergyDustInRoomHourlyUpdate)


MarTraits.allergyDustOnSquare = function()
	if player == nil then 
		player = getPlayer()
	end

	if not player:HasTrait("Mar_DustAllergic") or player:isAsleep() then
		dustSquare = 0
		return
	end

	--print("--== Dust Debugger ==--")
	local square = getCell():getGridSquare(player:getX(),player:getY(),player:getZ())

	if square == nil then 
		dustSquare = 0
		return 
	end

	local dustSum = MarTraits.sumDustInSquare(square)
	if player:isOutside() then
		dustSum = dustSum * 0.2 -- When outside, "dust" tiles have reduced effect.
	end

	--print("Dust In Player Square: ",dustSum)

	dustSquare = dustSum 
end
Events.EveryOneMinute.Add(MarTraits.allergyDustOnSquare)

MarTraits.treePollenClothesUpdate = function()
	if player == nil then
		player = getPlayer()
	end

	if player:isInTrees() then
		MarTraits.addClothesPollen(player,0.1) -- Add 10% max pollen on clothes items when walking through trees
		print("======== ADDED CLOTHES POLLEN ==========")
	end
end
Events.EveryOneMinute.Add(MarTraits.treePollenClothesUpdate)


MarTraits.updateAllergicTraitMoodleData = function(player)
	local moodle = nil
	if MarTraits.moodleFrameworkActive then
		moodle = MF.getMoodle("Allergies", player:getPlayerNum())
	end
	--print("total level of " .. MarTraits.getSeasonAllergyLevel(player) + MarTraits.getDustAllergyLevel(player))
	print("Count gradual change of " .. countGradualChange)
	print("Count spike change of " .. countSpikeChange)
	-- Based off the levels of requirement for count change, but with spike removed.
	MarTraits.allergiesMoodleSavedValue = PZMath.lerp(1, 0, -countGradualChange/(countChangeGradualMoodleActivateThreshold*5)) -- 5, because 5 moodle levels.
	-- If moodle should show because of a spike, such as with trees, bump it to do so, since want to communicate that, and allow for SNEEZES.
	if countSpikeChange < countSpikeMoodleActivateThreshold then
		MarTraits.allergiesMoodleSavedValue = MarTraits.allergiesMoodleSavedValue - (MarTraits.moodleStepAmount) - 0.01 -- 0.01 so it beats threshold.
	end

	MarTraits.allergiesMoodleSavedValue = PZMath.clamp(MarTraits.allergiesMoodleSavedValue, 0, 1)

	print("Moodle Value = " .. MarTraits.allergiesMoodleSavedValue)

	if MarTraits.allergiesMoodleSavedValue <= MarTraits.moodleAllergiesBad1 then
		MarTraits.allergiesMoodleActive = true
	elseif MarTraits.allergiesMoodleActive == true then
		-- Disable it a bit after a check, so the moodle doesn't pop in and out of existance too fast.
		-- TODO: probably change this to be based off how much count gain there was instead, so count gain makes take longer to vanish?
		MarLibrary.delayFuncByDelta(
			function()
				-- If should still be showing, don't cancel.
				if MarTraits.allergiesMoodleSavedValue > MarTraits.moodleAllergiesBad1 then
					MarTraits.allergiesMoodleActive = false
				end
			end
			, 4
		)
	end

	-- If the moodle mod exists, set the visual moodle to show it.
	if moodle then
		-- Small check to make sure visual moodle never goes too high.
		moodle:setValue(MarTraits.allergiesMoodleSavedValue)
	end	
end

local function allergicSneezeUpdate()	
	if player == nil then 
		player = getPlayer()
	end
	
	if player:isAsleep() then
		return
	end 
	
	local hasSeasonalAllergies = player:HasTrait("Mar_SeasonAllergic")
	local hasDustAllergies = player:HasTrait("Mar_DustAllergic")

	if hasSeasonalAllergies or hasDustAllergies then
		countGradualChange = 0.0 --Reset gradual change at start.

		if hasSeasonalAllergies then
			local allergyDelta = 0.0

			local climate = getWorld():getClimateManager()
			
			--print("Wind speed is: ",climate:getWindspeedKph() / 40.0)
			--print("Speed Lerp: ",PZMath.lerp(-0.2, -1.0, climate:getWindspeedKph() / 40.0))
			local windDelta = PZMath.clamp(PZMath.lerp(-0.2, -1.0, (climate:getWindspeedKph() / 40.0)), -0.2, -1.0) -- With no wind, modify seasonal allergy effect by the first argument, with max wind, modify by second argument.

			local rainDelta = 0.0
			if climate:getRainIntensity() > 0 then
				rainDelta = PZMath.lerp(1.0, 5.0, (climate:getRainIntensity())) --Rain will restore the counter.
			end

			local insideMod = 1.0 --Wind and rain are divided by this number.
			if not player:isOutside() then
				insideMod = 3.0
			end

			local treeDelta = 0.0
			if player:isInTrees() then
				treeDelta = -10.0
			end
			
			local clothesDelta = PZMath.lerp(0.0, -1.0, totalPollen) --Every "full" clothes item will incur the set cost.

			--Accumulate all effects and then update player allergy level.
			allergyDelta = allergyDelta + (((seasonDelta * windDelta) + rainDelta) / insideMod) + treeDelta + clothesDelta

			--If wearing mask, reduce effects of all deltas!
			if player:getWornItems():getItem("Mask") ~= nil then
				allergyDelta = allergyDelta * 0.75
			end

			-- TODO: change this code around so that recovery stuff is general not specific to this trait, and change how it decreases below.
			local oldLevel = MarTraits.getSeasonAllergyLevel(player)
			allergyDelta = allergyDelta + PZMath.lerp(baseAllergyRecoveryRate, baseAllergyRecoveryRate * proportionalAllergyRecoveryRate, 1.0 - oldLevel)
			local newLevel = MarTraits.setSeasonAllergyLevel(player, oldLevel + (allergyDelta * allergyRate)) 

			local addedGradualChange = 0
			local addedSpikeChange = 0

			if newLevel <= MarTraits.moodleAllergiesBad1 then
				addedGradualChange = PZMath.lerp(-15.0, -0.1, newLevel - (1.0 - MarTraits.moodleAllergiesBad1))
			end

			print(string.format("SeasonalAllergy %.2f | Delta %.2f | Season %.2f | Wind %.2f | Rain %.2f | Clothes %.2f | Trees %.2f", newLevel, allergyDelta, seasonDelta, windDelta, rainDelta, clothesDelta, treeDelta))

			--print("Sneeze Change: ",countGradualChange)
			if treeDelta < 0 then
				print("In trees!")
				addedSpikeChange = addedSpikeChange + treeSneezeCost * seasonDelta -- Standing in trees subtracts seconds from sneeze for quick feedback/consequences
			end

			countSpikeChange = countSpikeChange + addedSpikeChange
			countGradualChange = countGradualChange + addedGradualChange
		end

		if hasDustAllergies then
			local allergyDelta = 0.0

			dustRoomRatio = 0
			if roomSquareSize ~= 0 then -- To prevent divide by zero scenarios.
				dustRoomRatio = (dustRoom / roomSquareSize) or 0
			end

			allergyDelta = allergyDelta + (dustRoomRatio * dustRoomMod) + (dustSquare * dustSquareMod)

			--If wearing mask, reduce effects of all deltas!
			if player:getWornItems():getItem("Mask") ~= nil then
				allergyDelta = allergyDelta * 0.75
			end

			local oldLevel = MarTraits.getDustAllergyLevel(player)

			allergyDelta = allergyDelta + PZMath.lerp(baseAllergyRecoveryRate, baseAllergyRecoveryRate * proportionalAllergyRecoveryRate, 1.0 - oldLevel)

			local newLevel = MarTraits.setDustAllergyLevel(player, oldLevel + (allergyDelta * allergyRate))

			local addedGradualChange = 0
			if newLevel <= MarTraits.moodleAllergiesBad1 then
				addedGradualChange = PZMath.lerp(-5.0, -0.1, newLevel - (1.0 - MarTraits.moodleAllergiesBad1))
			else
				addedGradualChange = PZMath.lerp(0.0, 1.0, newLevel - MarTraits.moodleAllergiesBad1)
			end

			print(string.format("DustAllergy %.2f | Delta %.2f | Room %.2f | Square %.2f", newLevel, allergyDelta, dustRoomRatio * dustRoomMod, dustSquare * dustSquareMod))

			countGradualChange = countGradualChange + addedGradualChange
		end

		MarTraits.updateAllergicTraitMoodleData(player)
		-- Reset count for sneeze since we use it.
		countSpikeChange = 0.0

		if not MarTraits.allergiesMoodleActive then --After we checked sneezeCountdown <= 0
			return --Abort if no moodle is showing!
		end

		-- Add together the thingies for sneeze countdown.
		MarTraits.setSneezeCountdown(player, MarTraits.getSneezeCountdown(player) + countGradualChange + countSpikeChange)
		print("Sneeze Countdown: ",MarTraits.getSneezeCountdown(player))

		if MarTraits.getSneezeCountdown(player) <= 0 then
			-- Do a wiggle with the sneeze, thematics!
			local moodle = MF.getMoodle("Allergies", player:getPlayerNum())
			if moodle then
				moodle:doWiggle()
			end

			MarTraits.resetSneezeCountdown()

			--print("=========== Sneeze Triggered ============")
			local volume = sneezeSoundVolume
			local range = sneezeSoundRange
			if player:getBodyDamage():isHasACold() then
				volume = volume * sneezeColdMod
				range = range * sneezeColdMod
			end

			local itemPrimaryHand = player:getPrimaryHandItem()
			local itemSecondaryHand = player:getSecondaryHandItem()
			-- "Sneezing Tissue" by Hea
			if player:hasEquipped("Base.ToiletPaper") or player:hasEquipped("Base.Tissue") then
				if ZombRand(0,100) <= tissueUseChance then
					if itemPrimaryHand and itemPrimaryHand:getType() == "ToiletPaper" then
						itemPrimaryHand:Use()
					elseif itemSecondaryHand and itemSecondaryHand:getType() == "ToiletPaper" then
						itemSecondaryHand:Use()
					elseif itemPrimaryHand and itemPrimaryHand:getType() == "Tissue" then
						itemPrimaryHand:Use()
					elseif itemSecondaryHand and itemSecondaryHand:getType() == "Tissue" then
						itemSecondaryHand:Use()
					end
				end
				player:getBodyDamage():setSneezeCoughActive(3)
				if sneezeMuteMod > 0 then
					addSound(player, player:getX(), player:getY(), player:getZ(), range * sneezeMuteMod, volume * sneezeMuteMod);
				end
				-- If sneezeMuteMod == 0, then no sound is played!

			else -- "Sneezing No Tissue" by Hea
				player:getBodyDamage():setSneezeCoughActive(1)
				addSound(player, player:getX(), player:getY(), player:getZ(), range, volume);
			end

			MarLibrary.delayFuncByDelta(
				function()
					print("Disable allergy sneeze!")
					player:getBodyDamage():setSneezeCoughActive(0) --Disable sneezing
				end
				, 0.3)

		else
			--Run "buildup" code, to give player some warning of sneeze
			if countGradualChange + countSpikeChange < 0 then
				local updatesToSneeze = PZMath.abs(MarTraits.getSneezeCountdown(player) / (countGradualChange + countSpikeChange))
				local buildupChance = PZMath.lerp(75, 15, (updatesToSneeze-1) / 6) --Scale chance, depending on updates remaining
				print("Updates to sneeze : ",updatesToSneeze," Buildup Chance : ",buildupChance)
				if ZombRand(100) <= buildupChance then
					if updatesToSneeze < 1 then
						player:SayShout("AHH!")
					elseif updatesToSneeze < 3 then
						player:Say("Hahh...")
					else
						player:Say("*sniff*")
					end
				end
			end
		end
	end
end
Events.EveryOneMinute.Add(allergicSneezeUpdate)

local function allergicOnPlayerDoTimedAction(player, action)
	-- If allergic and transferring, check for dusty-ness for a spike.
	if player:HasTrait("Mar_DustAllergic") and action:getMetaType() == "ISInventoryTransferAction" then
		
		local delta = getGameTime():getTimeDelta() -- So it doesn't change with frame rate.
		local allergySpike = 0.0

		allergySpike = allergySpike + (dustRoomRatio * rummageDustRoomRatioSpikeMod * delta)
		allergySpike = allergySpike + (dustSquare * rummageDustSquareSpikeMod * delta)
		countSpikeChange = countSpikeChange + allergySpike

		-- Update so moodle changes.
		MarTraits.updateAllergicTraitMoodleData(player)
	end
end
MarLibrary.Events.OnPlayerDoTimedAction:Add("allergicOnPlayerDoTimedAction", allergicOnPlayerDoTimedAction)