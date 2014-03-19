<#
.SYNOPSIS
A Rogue-like game written in PowerShell. Inspired by the classic PC game Rogue and written to allow others to learn PowerShell in a fun way. Written by Emre Motan.

.DESCRIPTION
The Get-Inventory function uses Windows Management Instrumentation (WMI) toretrieve service pack version, operating system build number, and BIOS serial number from one or more remote computers. 
Computer names or IP addresses are expected as pipeline input, or may bepassed to the –computerName parameter. 
Each computer is contacted sequentially, not in parallel.

.PARAMETER computerNameAccepts 
a single computer name or an array of computer names. You mayalso provide IP addresses.

.PARAMETER path
The path and file name of a text file. Any computers that cannot be reached will be logged to this file. 
This is an optional parameter; if it is notincluded, no log file will be generated.

.EXAMPLE
Read computer names from Active Directory and retrieve their inventory information.
Get-ADComputer –filter * | Select{Name="computerName";Expression={$_.Name}} | Get-Inventory.

.EXAMPLE 
Read computer names from a file (one name per line) and retrieve their inventory information
Get-Content c:\names.txt | Get-Inventory.

.NOTES
You need to run this function as a member of the Domain Admins group; doing so is the only way to ensure you have permission to query WMI from the remote computers.
#>

<#
PowerRogue Design

v1
Player character is of one class, SysAdmin. Stats include "concentration" e.g. health, "SkillSet" e.g. attack power, "Knowledge" which is experience, "Position" which is level (e.g. Junior, regular, senior, lead...).
Player provides a name.
Game has a title screen with colorful "PowerRogue" art.
Goal is to ascend levels of the office building to reach the Tome of Productivity.
Enemies get progressively more difficult. Set # of enemies per level.
Enemies:
- Spam lvl 1
- Bug lvl 2
- Virus lvl 3
- Meeting lvl 4
- Ambiguity lvl 5
Can pick up "money" along the way. Enemies drop them.
Granted "Knowledge" when enemy is defeated.
Leveling up "Knowledge" increases SkillSet and Concentration.
Maps are randomly generated "Rogue-Like"
Stairways are point between levels. Cannot go back up stairs - stairway disappears.

Controls:
Arrow keys are all that's needed.
'q' saves and quits the game.

GameFlow:
- Title Screen
- Ask for name
- Create level 1
- Player reaches stairway
- Create level 2
...
- Player reaches stairway on level 5
- Game End Screen
-- Shows all stats, money, congratulations

Objects:
- Current level Map
- Game global info
- Player
- Enemies dictionary
- Enemies on current level

TODO:
- Help screen (F1)

#>

$debugOutput = 0

# Display welcome screen
Clear-Host
Write-Host 'Welcome to PowerRogue, the Rogue-like game written in PowerShell'

# Ask for player's name
$name = Read-Host "`nWhat is the player's name?"

$playerClass = @"
// Stats include "concentration" e.g. health, "SkillSet" e.g. attack power, "Knowledge" which is experience, 
// "PositionLevel" which is level (e.g. Junior, regular, senior, lead...).
public class Player
{
    public int xPos;
	public int yPos;
	
	public int concentration;
	public int skillSet;
	public int knowledge;
	public int positionLevel;
	
	public int money;
	
	public string name; // String works; don't need to use char[]
}
"@

# Player initialization
Add-Type -TypeDefinition $playerClass
$player = New-Object Player
$player.xPos = 1
$player.yPos = 1
$player.name = $name
$player.concentration = 10
$player.skillSet = 1
$player.knowledge = 1
$player.positionLevel = 1
$player.money = 0

# Function to check position the player wants to go walk onto
# For now, just check if the tile is walkable
# Can be used for both player and NPCs
Function CheckDestTileWalkable
{
    if ($destX -lt 30 -and $destY -lt 30 `
	    -and $destX -ge 0 -and $destY -ge 0)
	{
	    $i = $Global:floorData[$destY][$destX]
		if ($i -eq 46 -or `
		    $i -eq "<" -or `
			$i -eq "*")
		{
	    	$walkableFlg = 1
		}
		else
		{
		    $walkableFlg = 0
	    }
	}
	else
	{
		$walkableFlg = 0
	}

	return $walkableFlg
}

# Array to hold descriptions of actions taken
$Global:actionLog = @()
$gameLevel = 1

# As long as $running == 1, the game's main loop... loops
$running = 1
$foundTome = 0

# TODO:
# Randomly sized room
# Place enemies on map based on level (level 1 = one enemy, level 2 = two enemies, etc...)
# Goal is to get treasure and call enemies

$Global:RoomClass = @"
public class Room
{
    public int numGridPos;
	public int xGridPos;
	public int yGridPos;
	
	public int xSize;
	public int ySize;
	
	public int xOffset;
	public int yOffset;
	
	public int connectedFlg;
	
	public int numNeighbors;
	public int[] neighborGridNum = new int[4]; // Maximum neighbor of neighbors is four
}
"@
Add-Type -TypeDefinition $Global:RoomClass
$Global:Room = @(New-Object Room)

$Global:CorridorClass = @"
public class Corridor
{
    public int startNumGrid;
	public int endNumGrid;
}
"@
Add-Type -TypeDefinition $Global:CorridorClass

$Global:floorData = @()

function CreateLevel
{
    # Generate Rooms
    $Global:Room[0].numGridPos = 0
	$Global:Room[0].xGridPos   = 0
	$Global:Room[0].yGridPos   = 0
	$Global:Room[0].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[0].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[0].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[0].xOffset)
	$Global:Room[0].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[0].yOffset)
	$Global:Room[0].connectedFlg = 0
	$Global:Room[0].numNeighbors = 2
	$Global:Room[0].neighborGridNum[0] = 1
	$Global:Room[0].neighborGridNum[1] = 3
	
	$Global:Room += @(New-Object Room)
	
	$Global:Room[1].numGridPos = 1
	$Global:Room[1].xGridPos   = 10
	$Global:Room[1].yGridPos   = 0
	$Global:Room[1].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[1].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[1].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[1].xOffset)
	$Global:Room[1].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[1].yOffset)
	$Global:Room[1].connectedFlg = 0
	$Global:Room[1].numNeighbors = 3
	$Global:Room[1].neighborGridNum[0] = 0
	$Global:Room[1].neighborGridNum[1] = 2
	$Global:Room[1].neighborGridNum[2] = 4
    
    $Global:Room += @(New-Object Room)
    
    $Global:Room[2].numGridPos = 2
	$Global:Room[2].xGridPos   = 20
	$Global:Room[2].yGridPos   = 0
	$Global:Room[2].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[2].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[2].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[2].xOffset)
	$Global:Room[2].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[2].yOffset)
	$Global:Room[2].connectedFlg = 0
	$Global:Room[2].numNeighbors = 2
	$Global:Room[2].neighborGridNum[0] = 1
	$Global:Room[2].neighborGridNum[1] = 5
	
    
    $Global:Room += @(New-Object Room)
    
    $Global:Room[3].numGridPos = 3
	$Global:Room[3].xGridPos   = 0
	$Global:Room[3].yGridPos   = 10
	$Global:Room[3].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[3].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[3].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[3].xOffset)
	$Global:Room[3].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[3].yOffset)
	$Global:Room[3].connectedFlg = 0
    $Global:Room[3].numNeighbors = 3
	$Global:Room[3].neighborGridNum[0] = 0
	$Global:Room[3].neighborGridNum[1] = 4
	$Global:Room[3].neighborGridNum[2] = 6
	
    $Global:Room += @(New-Object Room)
    
    $Global:Room[4].numGridPos = 4
	$Global:Room[4].xGridPos   = 10
	$Global:Room[4].yGridPos   = 10
	$Global:Room[4].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[4].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[4].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[4].xOffset)
	$Global:Room[4].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[4].yOffset)
	$Global:Room[4].connectedFlg = 0
	$Global:Room[4].numNeighbors = 4
	$Global:Room[4].neighborGridNum[0] = 1
	$Global:Room[4].neighborGridNum[1] = 3
	$Global:Room[4].neighborGridNum[2] = 7
	$Global:Room[4].neighborGridNum[3] = 5
    
    $Global:Room += @(New-Object Room)
    
    $Global:Room[5].numGridPos = 5
	$Global:Room[5].xGridPos   = 20
	$Global:Room[5].yGridPos   = 10
	$Global:Room[5].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[5].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[5].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[5].xOffset)
	$Global:Room[5].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[5].yOffset)
	$Global:Room[5].connectedFlg = 0
    $Global:Room[5].numNeighbors = 3
	$Global:Room[5].neighborGridNum[0] = 2
	$Global:Room[5].neighborGridNum[1] = 4
	$Global:Room[5].neighborGridNum[2] = 8
	
    $Global:Room += @(New-Object Room)
    
    $Global:Room[6].numGridPos = 6
	$Global:Room[6].xGridPos   = 0
	$Global:Room[6].yGridPos   = 20
	$Global:Room[6].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[6].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[6].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[6].xOffset)
	$Global:Room[6].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[6].yOffset)
	$Global:Room[6].connectedFlg = 0
    $Global:Room[6].numNeighbors = 2
	$Global:Room[6].neighborGridNum[0] = 3
	$Global:Room[6].neighborGridNum[1] = 7
	
    $Global:Room += @(New-Object Room)
    
    $Global:Room[7].numGridPos = 7
	$Global:Room[7].xGridPos   = 10
	$Global:Room[7].yGridPos   = 20
	$Global:Room[7].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[7].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[7].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[7].xOffset)
	$Global:Room[7].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[7].yOffset)
	$Global:Room[7].connectedFlg = 0
	$Global:Room[7].numNeighbors = 3
	$Global:Room[7].neighborGridNum[0] = 6
	$Global:Room[7].neighborGridNum[1] = 4
	$Global:Room[7].neighborGridNum[2] = 8
    
    $Global:Room += @(New-Object Room)
    
    $Global:Room[8].numGridPos = 8
	$Global:Room[8].xGridPos   = 20
	$Global:Room[8].yGridPos   = 20
	$Global:Room[8].xOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[8].yOffset    = Get-Random -Minimum 1 -Maximum 3
	$Global:Room[8].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[8].xOffset)
	$Global:Room[8].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[8].yOffset)
	$Global:Room[8].connectedFlg = 0
	$Global:Room[8].numNeighbors = 2
	$Global:Room[8].neighborGridNum[0] = 7
	$Global:Room[8].neighborGridNum[1] = 5
	
	$firstGridNum = Get-Random -Minimum 0 -Maximum 8
	$currentGridNum = $firstGridNum
	$Global:Room[$currentGridNum].connectedFlg = 1
	$Global:CorridorIndexNum = 0
	$numCorridors
	
	# Generate Corridors
	$Global:RoomLooping = 1
	while ($Global:RoomLooping -eq 1)
	{
	    $searchForNeighbor = 1
		$searchLoopNum = 0
		$neighborFoundFlg = 0
		
		$neighborIndexArray = @()
		for($i=0; $i -lt $Global:Room[$currentGridNum].numNeighbors; $i++)
		{
		    $neighborIndexArray += @($i)
		}
		
		$neighborIndexArray = $neighborIndexArray | sort {[System.Guid]::NewGuid()}
		
		for($i=0; $i -lt $Global:Room[$currentGridNum].numNeighbors -and $neighborFoundFlg -eq 0; $i++)
		{
			#$randIndexNum = Get-Random -Minimum 0 -Maximum ($Global:Room[$currentGridNum].numNeighbors - 1)
			$randIndexNum = $neighborIndexArray[$i]
			$targetGridNum = $Global:Room[$currentGridNum].neighborGridNum[$randIndexNum]
			
			#Write-Host "Attempting to connect" $currentGridNum "to" $targetGridNum
			if($Global:Room[$targetGridNum].connectedFlg -eq 0)
			{
			    $Global:Room[$targetGridNum].connectedFlg = 1
				
				$Global:Corridor += @(New-Object Corridor)
			    $Global:Corridor[$Global:CorridorIndexNum].startNumGrid = $currentGridNum
				$Global:Corridor[$Global:CorridorIndexNum].endNumGrid = $targetGridNum
				$Global:CorridorIndexNum++
				
				if($debugOutput -eq 1) {Write-Host "Connected room" $currentGridNum " to room" $targetGridNum}
				
				$numCorridors++
				
				$currentGridNum = $targetGridNum
				$searchForNeighbor = 0
				$neighborFoundFlg = 1
			}
		}
			
		# Check to see if all rooms are connected
		# If not, randomly select the $currentGridNum and loop again
		$numConnectedRooms = 0
		for($i=0;$i -lt 9; $i++)
		{
		    if($Global:Room[$i].connectedFlg -eq 1)
			{
			    $numConnectedRooms++
			}
		}
				
		if($numConnectedRooms -ge 9)
		{
		    $Global:RoomLooping = 0
		}
		elseif($neighborFoundFlg -eq 0)
		{
		    $currentGridNum = Get-Random -Minimum 0 -Maximum 8
			$Global:Room[$currentGridNum].connectedFlg = 1
			if($debugOutput -eq 1) {Write-Host "Random grid" $currentGridNum}
		}
	}
	
	$lastGridNum = $currentGridNum
	
	# Generate a few more random corridors
	# First see if there are any unconnected rooms and connect them
	for($i=0;$i -lt 9; $i++)
	{
	    if($Global:Room[$i].connectedFlg -eq 0)
		{
			$currentGridNum = $i
			$neighborIndexArray = @()
			for($t=0; $t -lt $Global:Room[$currentGridNum].numNeighbors; $t++)
			{
			    $neighborIndexArray += @($t)
			}
		
		    $neighborIndexArray = $neighborIndexArray | sort {[System.Guid]::NewGuid()}
			$randIndexNum = $neighborIndexArray[0]
			$targetGridNum = $Global:Room[$currentGridNum].neighborGridNum[$randIndexNum]
			
			$Global:Room[$i].connectedFlg = 1
				
			$Global:Corridor += @(New-Object Corridor)
			$Global:Corridor[$Global:CorridorIndexNum].startNumGrid = $currentGridNum
			$Global:Corridor[$Global:CorridorIndexNum].endNumGrid = $targetGridNum
						
			if($debugOutput -eq 1) {Write-Host "Connected room" $currentGridNum " to room" $targetGridNum " (post-attribution)"}
		}
	}

	# Then generate up to rand(gridWidthSize) total corridors
	$numRandCorridorsToGen = Get-Random -Minimum 1 -Maximum 2
	$numRandCorridors = 0
	while($numRandCorridors -lt $numRandCorridorsToGen)
	{
		# Choose random room
		$currentGridNum = Get-Random -Minimum 0 -Maximum 8
		
		# Choose random neighbor and make corridor (don't yet check if that corridor already exists)
		$neighborIndexArray = @()
		for($t=0; $t -lt $Global:Room[$currentGridNum].numNeighbors; $t++)
		{
		    $neighborIndexArray += @($t)
		}
		$neighborIndexArray = $neighborIndexArray | sort {[System.Guid]::NewGuid()}
		$randIndexNum = $neighborIndexArray[0]
		$targetGridNum = $Global:Room[$currentGridNum].neighborGridNum[$randIndexNum]
		
		# Check to see if this corridor already exists
		$dupCorridor = 0
	    for($i=0;$i -lt $numCorridors;$i++)
		{
		    if(($Global:Corridor[$i].startNumGrid -eq $currentGridNum -and $Global:Corridor[$i].endNumGrid -eq $targetGridNum) `
			   -or ($Global:Corridor[$i].endNumGrid -eq $currentGridNum -and $Global:Corridor[$i].startNumGrid -eq $targetGridNum))
			{
				$dupCorridor = 1
			}
		}
		
		# If the corridor does not exist, create it
		if($dupCorridor -eq 0)
		{
			$Global:Corridor += @(New-Object Corridor)
			$Global:Corridor[$Global:CorridorIndexNum].startNumGrid = $currentGridNum
			$Global:Corridor[$Global:CorridorIndexNum].endNumGrid = $targetGridNum
		
			$numCorridors++
			$numRandCorridors++
		}
	
		if($debugOutput -eq 1) {Write-Host "Connected room" $currentGridNum " to room" $targetGridNum " (random)"		}
	}
	
	if($debugOutput -eq 1) {Write-Host "start $startGridNum end $endGridNum"}
	
	# Room Data
	# Create large, empty room
	# 30x30, like Pixel Dungeon (Android)
	$Global:floorData = @(
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ),
	   ( 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 )
	)

    # Draw rooms (first implementation)
	for ($n=0; $n -lt 9; $n++)
	{	
	    $yStart = $Global:Room[$n].yGridPos + $Global:Room[$n].yOffset
		$yEnd = $yStart + $Global:Room[$n].ySize
		
		$xStart = $Global:Room[$n].xGridPos + $Global:Room[$n].xOffset
		$xEnd = $xStart + $Global:Room[$n].xSize
	
		for ($y=$yStart; $y -le $yEnd; $y++)
		{
		    for ($x=$xStart; $x -le $xEnd; $x++)
			{
			    $Global:floorData[$y][$x] = 46
			}
		}
		if($debugOutput -eq 1) {Write-Host "Drew room" $n}
	}
		
	# Draw Corridors
	for($i=0; $i -lt $numCorridors; $i++)
	{
	    $startGridNum =	$Global:Corridor[$i].startNumGrid
		$endGridNum = $Global:Corridor[$i].endNumGrid
		$startX = $Global:Room[$startGridNum].xGridPos + 4
		$startY = $Global:Room[$startGridNum].yGridPos + 4
		$endX = $Global:Room[$endGridNum].xGridPos + 4
		$endY = $Global:Room[$endGridNum].yGridPos + 4
		
		if($startX -gt $endX)
		{
		    $intX = $endX
			$endX = $startX
			$startX = $intX
		}
		
		if($startY -gt $endY)
		{
		    $intY = $endY
			$endY = $startY
			$startY = $intY
		}
		
		
		for($y=$startY; $y -le $endY; $y++)
		{
		    for($x=$startX; $x -le $endX; $x++)
			{
			    $Global:floorData[$y][$x] = 46
			}
		}
		
	    if($debugOutput -eq 1) {Write-Host "Drew corridor" $i "from room" $Global:Corridor[$i].startNumGrid" ($startX,$startY) to "$Global:Corridor[$i].endNumGrid" ($endX,$endY)"}
	}
	
    # Draw walls
	# | vertical wall
	# - horizonal wall
	# Loop over entire $Global:floorData
	# When tile = 0 and [y+1][x] = 46 and y < 30, set to 45
	# When tile = 0 and [y-1][x] = 46 and y > 0,  set to 45
	# When tile = 0 and [x+1][x] = 46 and x < 30, set to 124
	# When tile = 0 and [x-1][x] = 46 and x > 0,  set to 124
		
	for ($y=0; $y -lt 30; $y++)
	{
	    for ($x=0; $x -lt 30; $x++)
		{
		    if($Global:floorData[$y][$x] -eq 0 -and $y -lt 29 -and $Global:floorData[($y+1)][$x] -eq 46 -and $Global:floorData[$y][$x] -ne 46)
			{
			     $Global:floorData[$y][$x] = 45
			}
			elseif($Global:floorData[$y][$x] -eq 0 -and $y -gt 0 -and $Global:floorData[($y-1)][$x] -eq 46 -and $Global:floorData[$y][$x] -ne 46)
			{
			    $Global:floorData[$y][$x] = 45
			}
			elseif($Global:floorData[$y][$x] -eq 0 -and $x -lt 29 -and $Global:floorData[$y][($x+1)] -eq 46 -and $Global:floorData[$y][$x] -ne 46)
			{
			    $Global:floorData[$y][$x] = 124
			} 
			elseif($Global:floorData[$y][$x] -eq 0 -and $x -gt 0 -and $Global:floorData[$y][($x-1)] -eq 46 -and $Global:floorData[$y][$x] -ne 46)
			{
				$Global:floorData[$y][$x] = 124
			}
		}	
	}
	
	if($debugOutput -eq 1) {$inputKey = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")	}
	
	# Create room (debug algorithm)
	<#
	for ($y=0; $y -lt 30; $y++)
	{
	    for ($x=0; $x -lt 30; $x++)
		{
		    if ($y -eq 0 -or $y -eq 30 - 1)
			{
			    $Global:floorData[$y][$x] = 45
		  	}
		    elseif ($x -eq 0 -or $x -eq 30 - 1)
			{
			    $Global:floorData[$y][$x] = 124
			}
			else
			{
			    $Global:floorData[$y][$x] = 46
			}
		}
	}
	#>
	
	# Place stairs up if Level 1 - 4
	if($gameLevel -lt 5)
	{
	    # Set stair location
   	    $xPos = $Global:Room[$lastGridNum].xGridPos + $Global:Room[$lastGridNum].xOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$lastGridNum].xSize)
	    $yPos = $Global:Room[$lastGridNum].yGridPos + $Global:Room[$lastGridNum].yOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$lastGridNum].ySize)
	
	    $Global:floorData[$yPos][$xPos] = "<"
	}
	
	# Place Tome of Productivity if Level 5
	if($gameLevel -eq 5)
	{
		# Set Tome location
   	    $xPos = $Global:Room[$lastGridNum].xGridPos + $Global:Room[$lastGridNum].xOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$lastGridNum].xSize)
	    $yPos = $Global:Room[$lastGridNum].yGridPos + $Global:Room[$lastGridNum].yOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$lastGridNum].ySize)
	
	    $Global:floorData[$yPos][$xPos] = "*"
	}
	
    # Set player location
	$player.xPos = $Global:Room[$firstGridNum].xGridPos + $Global:Room[$firstGridNum].xOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$firstGridNum].xSize)
	$player.yPos = $Global:Room[$firstGridNum].yGridPos + $Global:Room[$firstGridNum].yOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$firstGridNum].ySize)
	
	$Global:actionLog += "Entering floor " + $gameLevel + " of the office building..."
	
	
	# Create enemies
	
	
}



CreateLevel

# Main game loop
do {
	Clear-Host
	$screenData = ''
	
	# Debug output
	if($debugOutput -eq 1) {$screenData += "PCx: $($player.xPos)" + "`n"}
	if($debugOutput -eq 1) {$screenData += "PCy: $($player.yPos)" + "`n"}
	if($debugOutput -eq 1) {$screenData += "WalkableFlg: $walkableFlg" + "`n"}
	if($debugOutput -eq 1) {$i = $Global:floorData[$player.yPos][$player.xPos]}
	if($debugOutput -eq 1) {$screenData += "MapTile: $i" + "`n"}
	
	$screenData += "Floor Level: $gameLevel" + "`n"
	$screenData += "" + "`n"
	
	# Draw screen
	# Originally I was drawing each tile of the map individually using Write-Host -NoNewLine
	# I optimized this proceedure by constructing a string $screen that builds up the screen data
	# piece by piece. This data is displayed to the screen just before the "wait for input" command
	# is called.
	for ($y=0; $y -lt 30; $y++)
	{
	    for ($x=0; $x -lt 30; $x++)
		{
		    $asciiCode = $Global:floorData[$y][$x]		
			
			# Draw the player character if we're processing its position
			if($x -eq $player.xPos -and $y -eq $player.yPos)
			{
			    $screenData += ([char]64)
			}
			elseif($Global:floorData[$y][$x] -eq 0)
			{
			    $screenData += " "
			}
			else
			# Draw map tile
			{
			    $screenData += ([char]$asciiCode)
			}
		}
		$screenData += "`n"
	}
	
	# Draw player stats
	$screenData += "Name: " + $player.name + " | Concentration: " + $player.concentration + " | SkillSet: " + $player.skillSet + " | Knowledge: " + $player.knowledge + " | Position: " + $player.positionLevel + " | Floor #: " + $gameLevel + "`n"
	
	# Draw action log
    # We can access the last element in an array by referring to [-1]. Similarly, the fifth from the end would be [-5].
	$screenData += "`n"
	$screenData += $Global:actionLog[-5] + "`n"
	$screenData += $Global:actionLog[-4] + "`n"
	$screenData += $Global:actionLog[-3] + "`n"
	$screenData += $Global:actionLog[-2] + "`n"
	$screenData += $Global:actionLog[-1] + "`n"
	
	#foreach ($command in $Global:actionLogReverse)
	#{
	#    $screenData += $command + "`n"
	#}
	
	# Display contents of Screen Data
	Write-Host $screenData
	
	# Get player input
	$inputKey = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")

	# process player input using VirtualKeyCodes
	switch ($inputKey.VirtualKeyCode)
	{
	    # case 'q' key: Exit game
		81 { $running = 0}
	
	    # case 'up' key: 
	    38 { 
		   $destX = $player.xPos
		   $destY = $player.yPos - 1
		   $walkableFlg = CheckDestTileWalkable
		
		   if ($walkableFlg -eq 1)
		   {
		       $player.xPos = $destX
			   $player.yPos = $destY
			   
			   
     		   $command = "Player moves north"
    		   $Global:actionLog += $command
		   }
		   else
		   {
		       $command = "Path blocked"
    		   $Global:actionLog += $command   
		   }
		}
	
	    # case 'down' key:
	    40 { 
		   $destX = $player.xPos
		   $destY = $player.yPos + 1
		   $walkableFlg = CheckDestTileWalkable
		
		   if ($walkableFlg -eq 1)
		   {
		       $player.xPos = $destX
			   $player.yPos = $destY
			   
               $command = "Player moves south"
    		   $Global:actionLog += $command
		   }
		   else
		   {
		       $command = "Path blocked"
    		   $Global:actionLog += $command   
		   }
		}
	
		# case 'left' key:
	    37 { 
		   $destX = $player.xPos - 1
		   $destY = $player.yPos
		   $walkableFlg = CheckDestTileWalkable
		
		   if ($walkableFlg -eq 1)
		   {
		       $player.xPos = $destX
			   $player.yPos = $destY
			   $player.yPos = $destY
			   
               $command = "Player moves west"
    		   $Global:actionLog += $command
		   }
		   else
		   {
		       $command = "Path blocked"
    		   $Global:actionLog += $command   
		   }
		}
	
		# case 'right' key:
	    39 { 
		   $destX = $player.xPos + 1
		   $destY = $player.yPos
		   $walkableFlg = CheckDestTileWalkable
		
		   if ($walkableFlg -eq 1)
		   {
		       $player.xPos = $destX
			   $player.yPos = $destY
			   $player.yPos = $destY
			   
               $command = "Player moves east"
    		   $Global:actionLog += $command
		   }
		   else
		   {
		       $command = "Path blocked"
    		   $Global:actionLog += $command   
		   }
		} 
		
		# Generate new level
		76 {
			CreateLevel
		}
	}
	
	# Check to see if we're on a stairway tile
	if($Global:floorData[$player.yPos][$player.xPos] -eq "<")
	{
		$gameLevel += 1
		CreateLevel
	}
	
	# Check to see if we're on the Tome of Productivity tile
	if($Global:floorData[$player.yPos][$player.xPos] -eq "*")
	{
		$running = 0
		$foundTome = 1
	}
	
}
while ($running -eq 1)

# Check to see if player beat the game
if($foundTome -eq 1)
{
	Clear-Host
	Write-Host "Congratulations! You can now go be productive! `n"
	
	#Display stats
	Write-Host "Final stats:"
	Write-Host "Player name:" $player.name
	Write-Host "Player concentration:" $player.concentration
	Write-Host "Player SkillSet:" $player.skillSet
	Write-Host "Player Knowledge:" $player.knowledge
	Write-Host "Player Position:" $player.positionLevel
	Write-Host ""
}