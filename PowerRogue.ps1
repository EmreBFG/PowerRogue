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

# Overwrte the Clear-Host function with the System.Console function to do the same thing but much faster.
# Reference: http://powershell.com/cs/blogs/tips/archive/2010/10/21/clearing-console-content.aspx
# Function Clear-Host { [System.Console]::Clear() }
# NOTE: This does not seem to reduce flickering, though I did not quantifiably test it.

# Display welcome screen
Clear-Host
Write-Host "Welcome to PowerRogue, the Rogue-like game written in PowerShell`n"
Write-Host "The goal of the game is to find the Tome of Productivity (symbol: *) on the fifth floor of the building."
Write-Host "You must navigate each floor of the office building to find the staircase to the next floor (symbol: <)."
Write-Host "Along the way, you will troubleshoot such tasks as Spam (s), Bugs (b), Viruses (v), Outages (o), and Meetings (m)."
Write-Host "Don't let your Concentration reach 0, or else it's time to go home for the day!"

# Ask for player's name
$name = Read-Host "`nWhat is the player's name?"

$Global:playerClass = @"
// Stats include "concentration" e.g. health, "SkillSet" e.g. attack power, "Knowledge" which is experience, 
// "positionTitle" which is level (e.g. Junior, regular, senior, lead...).
public class Player
{
    public int xPos;
    public int yPos;
    
    public int concentration;
    public int skillSet;
    public int knowledge;
    public string positionTitle;
    
    public int money;
    
    public string name; // String works; don't need to use char[]
    
    public int currentGridPos;
}
"@

$enemyTypeClass = @"
public class EnemyType
{
    public int enemyTypeID;
    public string name;
    public string ascii; // ASCII representation of enemy
    public int health;
    public int attackPower;
}
"@
Add-Type -TypeDefinition $Global:enemyTypeClass
$Global:EnemyTypes = @()
$Global:numEnemyTypes = 3

$enemyClass = @"
public class Enemy
{
    public int enemyID;
    public int isAwake;
    public int isActive;
    public int xPos;
    public int yPos;
    public int enemyTypeID;
    public int health;
}
"@
Add-Type -TypeDefinition $Global:enemyClass
$Global:Enemy = @()
$Global:numEnemies = 0

# Player initialization
Add-Type -TypeDefinition $Global:playerClass
$Global:player = New-Object Player
$Global:player.xPos = 1
$Global:player.yPos = 1
$Global:player.name = $name
$Global:player.concentration = 10
$Global:player.skillSet = 1
$Global:player.knowledge = 1
$Global:player.positionTitle = "Junior Sys Admin"
$Global:player.money = 0


# Initiate Enemy Types
$Global:EnemyTypes += @(New-Object EnemyType)
$Global:EnemyTypes[0].enemyTypeID = 0
$Global:EnemyTypes[0].name = "Spam"
$Global:EnemyTypes[0].ascii = "s"
$Global:EnemyTypes[0].health = 1
$Global:EnemyTypes[0].attackPower = 1

$Global:EnemyTypes += @(New-Object EnemyType)
$Global:EnemyTypes[1].enemyTypeID = 1
$Global:EnemyTypes[1].name = "Bug"
$Global:EnemyTypes[1].ascii = "b"
$Global:EnemyTypes[1].health = 2
$Global:EnemyTypes[1].attackPower = 2

$Global:EnemyTypes += @(New-Object EnemyType)
$Global:EnemyTypes[2].enemyTypeID = 2
$Global:EnemyTypes[2].name = "Virus"
$Global:EnemyTypes[2].ascii = "v"
$Global:EnemyTypes[2].health = 3
$Global:EnemyTypes[2].attackPower = 2

$Global:EnemyTypes += @(New-Object EnemyType)
$Global:EnemyTypes[3].enemyTypeID = 3
$Global:EnemyTypes[3].name = "Outage"
$Global:EnemyTypes[3].ascii = "o"
$Global:EnemyTypes[3].health = 4
$Global:EnemyTypes[3].attackPower = 2

$Global:EnemyTypes += @(New-Object EnemyType)
$Global:EnemyTypes[4].enemyTypeID = 4
$Global:EnemyTypes[4].name = "Meeting"
$Global:EnemyTypes[4].ascii = "m"
$Global:EnemyTypes[4].health = 5
$Global:EnemyTypes[4].attackPower = 3

# Return which Grid Position the given coordinate is in
# This will return the GridPos if in a room, not in a corridor. Otherwise, will return -1.
function GetGridPos($x, $y)
{
    $GridPos = -1
    
    # TODO: Make these dependent on the map's actual room dimensions
    if($x -ge 0  -and $x -le 9  -and $y -ge 0  -and $y -le 9)  { $GridPos = 0 }
    if($x -ge 10 -and $x -le 19 -and $y -ge 0  -and $y -le 9)  { $GridPos = 1 }
    if($x -ge 20 -and $x -le 29 -and $y -ge 0  -and $y -le 9)  { $GridPos = 2 }
    if($x -ge 0  -and $x -le 9  -and $y -ge 10 -and $y -le 19) { $GridPos = 3 }
    if($x -ge 10 -and $x -le 19 -and $y -ge 10 -and $y -le 19) { $GridPos = 4 }
    if($x -ge 20 -and $x -le 29 -and $y -ge 10 -and $y -le 19) { $GridPos = 5 }
    if($x -ge 0  -and $x -le 9  -and $y -ge 20 -and $y -le 29) { $GridPos = 6 }
    if($x -ge 10 -and $x -le 19 -and $y -ge 20 -and $y -le 29) { $GridPos = 7 }
    if($x -ge 20 -and $x -le 29 -and $y -ge 20 -and $y -le 29) { $GridPos = 8 }
    
    return $GridPos
}

# Function to check position the player wants to go walk onto
# For now, just check if the tile is walkable
# Can be used for both player and NPCs
Function CheckDestTileWalkableByPlayer($dX, $dY)
{
    if ($dX -lt 30 -and $dY -lt 30 `
        -and $dX -ge 0 -and $dY -ge 0)
    {
        $i = $Global:floorData[$dY][$dX]
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
    
    for($i = 0; $i -lt $Global:numEnemies; $i++)
    {
        # Return a value that indicates the player can attack the enemy in the target destination
        if($Global:Enemy[$i].xPos -eq $dX -and $Global:Enemy[$i].yPos -eq $dY -and $Global:Enemy[$i].isActive -eq 1)
        {
            $walkableFlg = 2
        }           
    }

    return $walkableFlg
}

Function CheckDestTileWalkableByEnemy($dX, $dY, $EnemyID)
{
    if ($dX -lt 30 -and $dY -lt 30 `
        -and $dX -ge 0 -and $dY -ge 0)
    {
        $i = $Global:floorData[$dY][$dX]
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
    
    # Return a value that indicates the enemy can atatck the player in the target destination
    if($Global:player.xPos -eq $dX -and $Global:player.yPos -eq $dY)
    {
        $walkableFlg = 2
    }
    
    for($i = 0; $i -lt $Global:numEnemies; $i++)
    {
        # Don't walk onto a fellow enemy
        if($Global:Enemy[$i].xPos -eq $dX -and $Global:Enemy[$i].yPos -eq $dY -and $Global:Enemy[$i].isActive -eq 1)
        {
            $walkableFlg = 0
        }           
    }

    return $walkableFlg
}

  

# Function to have player attack an enemy at a specified position
Function PlayerAttackEnemy($dX, $dY)
{
    $targetEnemy = -1
                
    for($i=0; $i -lt $Global:numEnemies; $i++)
    {
        if($Global:Enemy[$i].xPos -eq $destX -and $Global:Enemy[$i].yPos -eq $destY -and $Global:Enemy[$i].isActive -eq 1)
        {
            $targetEnemy = $i
        }
    }
    
    $playerAttack = $Global:player.skillSet
    $Global:Enemy[$targetEnemy].health -= $playerAttack
    
    $command = $Global:player.name + " hits " + $Global:EnemyTypes[$Global:Enemy[$targetEnemy].EnemyTypeID].name + " for " + $playerAttack + " damage"
    $Global:actionLog += $command   
    
    if($Global:Enemy[$targetEnemy].health -le 0)
    {
         $Global:Enemy[$targetEnemy].isActive = 0
         $Global:Enemy[$targetEnemy].isAwake = 0
         
        $command = $Global:EnemyTypes[$Global:Enemy[$targetEnemy].EnemyTypeID].name + " has been tamed!"
        $Global:actionLog += $command    
        
        $Global:player.knowledge += 1
        CheckPlayerLevelUp
    }
}

# Check to see if the player has leveld up
Function CheckPlayerLevelUp
{
    if($Global:player.positionTitle -eq "Junior Sys Admin" -and $Global:player.knowledge -ge 10)
    {
        $Global:player.positionTitle = "Sys Admin"
        
        $command = "$name has been promoted! Now a " + $Global:player.positionTitle
        $Global:actionLog += $command
    }
    elseif($Global:player.positionTitle -eq "Sys Admin" -and $Global:player.knowledge -ge 20)
    {
        $Global:player.positionTitle = "Senior Sys Admin"
        
        $command = "$name has been promoted! Now a " + $Global:player.positionTitle
        $Global:actionLog += $command
    }
    elseif($Global:player.positionTitle -eq "Senior Sys Admin" -and $Global:player.knowledge -ge 30)
    {
        $Global:player.positionTitle = "Lead Sys Admin"
        
        $command = "$name has been promoted! Now a " + $Global:player.positionTitle
        $Global:actionLog += $command
    }

}

# Function to have enemy attack player
Function EnemyAttackPlayer($enemyID)
{
    $Global:player.concentration -= $Global:EnemyTypes[$Global:Enemy[$enemyID].EnemyTypeID].attackPower
    
    $name = $Global:EnemyTypes[$Global:Enemy[$i].EnemyTypeID].name
    $command = "$name hits player for " + $Global:EnemyTypes[$Global:Enemy[$enemyID].EnemyTypeID].attackPower + " damage"
    $Global:actionLog += $command
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
$Global:visibleFloorData = @()

function CreateLevel
{
    # Generate Rooms
    $Global:Room[0].numGridPos = 0
    $Global:Room[0].xGridPos   = 0
    $Global:Room[0].yGridPos   = 0
    $Global:Room[0].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[0].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[1].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[1].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[2].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[2].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[3].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[3].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[4].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[4].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[5].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[5].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[6].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[6].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[7].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[7].yOffset    = Get-Random -Minimum 1 -Maximum 4
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
    $Global:Room[8].xOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[8].yOffset    = Get-Random -Minimum 1 -Maximum 4
    $Global:Room[8].xSize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[8].xOffset)
    $Global:Room[8].ySize      = Get-Random -Minimum 3 -Maximum (8 - $Global:Room[8].yOffset)
    $Global:Room[8].connectedFlg = 0
    $Global:Room[8].numNeighbors = 2
    $Global:Room[8].neighborGridNum[0] = 7
    $Global:Room[8].neighborGridNum[1] = 5
    
    $firstGridNum = Get-Random -Minimum 0 -Maximum 9
    $currentGridNum = $firstGridNum
    $Global:Room[$currentGridNum].connectedFlg = 1
    $Global:CorridorIndexNum = 0
    $forceCorridorFlg = 0
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
            if($Global:Room[$targetGridNum].connectedFlg -eq 0 -or $forceCorridorFlg -eq 1)
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
        # TODO: Add check to see if we're on the last grid number and, if so, do not connect it to the first grid number. This might cause a "direct exit" for the player.
        elseif($neighborFoundFlg -eq 0)
        {
            $currentGridNum = Get-Random -Minimum 0 -Maximum 9
            $Global:Room[$currentGridNum].connectedFlg = 1
            $forceCorridorFlg = 1
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
    # Don't let $firstGridPos connect to $lastGridPos since this would directly connect the player's starting position to the level exit
    $numRandCorridorsToGen = Get-Random -Minimum 1 -Maximum 2
    $numRandCorridors = 0
    while($numRandCorridors -lt $numRandCorridorsToGen)
    {
        # Choose random room
        $currentGridNum = Get-Random -Minimum 0 -Maximum 9
        
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
        
        # Check to see if this corridor creates direct exit from $firstGridPos to $lastGridPos
        $directExit = 0
        if(($currentGridNum -eq $firstGridNum -and $targetGridNum -eq $lastGridNum) -or ($currentGridNum -eq $lastGridNum -and $targetGridNum -eq $firstGridNum))
        {
            $directExit = 1
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
    
        if($debugOutput -eq 1) {Write-Host "Connected room" $currentGridNum " to room" $targetGridNum " (random)"        }
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
    
    # Visible Room Data
    # These values will be 0 for not drawn, 1 for visible or previously visible to player    
    # Create large, empty room
    # 30x30, like Pixel Dungeon (Android)
    $Global:visibleFloorData = @(
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
        $startGridNum =    $Global:Corridor[$i].startNumGrid
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
        
    # Draw vertical walls
    for ($y=0; $y -lt 30; $y++)
    {
        for ($x=0; $x -lt 30; $x++)
        {
            
            if($Global:floorData[$y][$x] -eq 0 -and $y -lt 29 -and ($Global:floorData[($y+1)][$x] -eq 46) -and $Global:floorData[$y][$x] -ne 46)
            {
                 $Global:floorData[$y][$x] = 45
            }
            elseif($Global:floorData[$y][$x] -eq 0 -and $y -gt 0 -and ($Global:floorData[($y-1)][$x] -eq 46) -and $Global:floorData[$y][$x] -ne 46)
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
    
    if($debugOutput -eq 1) {$inputKey = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")    }
    
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
        $xPos = $Global:Room[$lastGridNum].xGridPos + $Global:Room[$lastGridNum].xOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$lastGridNum].xSize )
        $yPos = $Global:Room[$lastGridNum].yGridPos + $Global:Room[$lastGridNum].yOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$lastGridNum].ySize )
    
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
    $Global:player.xPos = $Global:Room[$firstGridNum].xGridPos + $Global:Room[$firstGridNum].xOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$firstGridNum].xSize)
    $Global:player.yPos = $Global:Room[$firstGridNum].yGridPos + $Global:Room[$firstGridNum].yOffset + (Get-Random -Minimum 0 -Maximum $Global:Room[$firstGridNum].ySize)
    $Global:player.currentGridPos = GetGridPos $Global:player.xPos $Global:player.yPos
    # Expose the area of the map where the player is now located
    MakeVisibleFloorData $Global:player.currentGridPos
    
    # Submit action log message
    $Global:actionLog += "Entering floor " + $gameLevel + " of the office building..."
    
    # Create enemies
    # For first level, place three "apam" enemies
    # Place them anywhere but the $firstGridNum, which is where we put the player to start
    $Global:numEnemies = Get-Random -Minimum 6 -Maximum 10
    
    $minEnemyTypeID = $gameLevel - 2 #Get-Random's Minimum flag is inclusive
    if($minEnemyTypeID -le 0) { $minEnemyTypeID = 0 }
    $maxEnemyTypeID = $gameLevel # Get-Random's Maximum flag is exclusive
    if($maxEnemyTypeID -le 0) { $maxEnemyTypeID = 0 }
    

    for($i = 0; $i -lt $Global:numEnemies; $i++)
    {
        $enemyTypeID = 0
        $enemyTypeID = Get-Random -Minimum $minEnemyTypeID -Maximum $maxEnemyTypeID
        
        $targetGridNum = -1
        do
        {
            $targetGridNum = Get-Random -Minimum 0 -Maximum 9
        } while ($targetGridNum -eq $firstGridNum)
    
        $Global:Enemy += @(New-Object Enemy)
        $Global:Enemy[$i].isAwake = 0
        $Global:Enemy[$i].isActive = 1
        $Global:Enemy[$i].enemyTypeID = $enemyTypeID
        $Global:Enemy[$i].health = $Global:EnemyTypes[$Global:Enemy[$i].enemyTypeID].health
        $Global:Enemy[$i].enemyID = $i
        
        do
        {
            $locationOK = 1
        
            $targetRelRoomXPos = Get-Random -Minimum 1 -Maximum ($Global:Room[$targetGridNum].xSize + 1)
            $targetRelRoomYPos = Get-Random -Minimum 1 -Maximum ($Global:Room[$targetGridNum].ySize + 1)
            $Global:Enemy[$i].xPos = $Global:Room[$targetGridNum].xGridPos + $Global:Room[$targetGridNum].xOffset + $targetRelRoomXPos
            $Global:Enemy[$i].yPos = $Global:Room[$targetGridNum].yGridPos + $Global:Room[$targetGridNum].yOffset + $targetRelRoomYPos
            
            if($i -eq 0)
            {
                $locationOK = 1
            }
            else
            {
                for($j = 0; $j -lt $i; $j++)
                {
                    if($Global:Enemy[$i].xPos -eq $Global:Enemy[$j].xPos -and $Global:Enemy[$i].yPos -eq $Global:Enemy[$j].yPos)
                    {
                        $locationOK = 0
                    }
                }
            }
            
        } while ($locationOK -ne 1)

    }
}

# We will show the map grid-by-grid
function MakeVisibleFloorData($gridNum)
{
    $xStart = $Global:Room[$gridNum].xGridPos
    $xEnd = $xStart + 9
    #$xEnd = $Global:Room[$gridNum].xGridPos + $Global:Room[$gridNum].xOffset + $Global:Room[$gridNum].xSize + 1
    $yStart = $Global:Room[$gridNum].yGridPos
    $yEnd = $yStart + 9
    #$yEnd = $Global:Room[$gridNum].yGridPos + $Global:Room[$gridNum].yOffset + $Global:Room[$gridNum].ySize + 1
        
    for($y = $yStart; $y -le $yEnd; $y++)
    {
        for($x = $xStart; $x -le $xEnd; $x++)
        {
            $Global:visibleFloorData[$y][$x] = 1
        }
    
    }
}

CreateLevel

# Main game loop
do {
    Clear-Host
    $screenData = ''
    
    # Debug output
    if($debugOutput -eq 1) {$screenData += "PCx: $($Global:player.xPos)" + "`n"}
    if($debugOutput -eq 1) {$screenData += "PCy: $($Global:player.yPos)" + "`n"}
    if($debugOutput -eq 1) {$screenData += "WalkableFlg: $walkableFlg" + "`n"}
    if($debugOutput -eq 1) {$i = $Global:floorData[$Global:player.yPos][$Global:player.xPos]}
    if($debugOutput -eq 1) {$screenData += "MapTile: $i" + "`n"}
    if($debugOutput -eq 1) {$screenData += "PC Current Grid Pos:" + $Global:player.currentGridPos + "`n" }
    if($debugOutput -eq 1) {$screenData += "`n" }
    
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
            $tileDrawn = 0
            
            # Draw the player character if we're processing its position
            if($x -eq $Global:player.xPos -and $y -eq $Global:player.yPos)
            {
                $screenData += ([char]64)
                $tileDrawn = 1
            }
            
            # Loop through enemies and draw them if they are alive (isActive -eq 1)
            for($i = 0; $i -lt $Global:numEnemies; $i++)
            {
                if($Global:Enemy[$i].xPos -eq $x -and $Global:Enemy[$i].yPos -eq $y -and $Global:Enemy[$i].isActive -eq 1 -and $Global:visibleFloorData[$y][$x] -eq 1)
                {
                    $screenData += $Global:EnemyTypes[$Global:Enemy[$i].EnemyTypeID].ascii
                    $tileDrawn = 1
                }
            }
            
            # If tile is blank or the tile is not visible draw a blank space
            if($Global:floorData[$y][$x] -eq 0 -or $Global:visibleFloorData[$y][$x] -eq 0)
            {
                $screenData += " "
                $tileDrawn = 1
            }
            
            # If a tile hasn't been drawn, draw the map tile
            if($tileDrawn -eq 0)
            {
                $screenData += ([char]$asciiCode)
            }
        }
        $screenData += "`n"
    }
    
    # Draw player stats
    $screenData += "Name: " + $Global:player.name + " | Concentration: " + $Global:player.concentration + " | SkillSet: " + $Global:player.skillSet + " | Knowledge: " + $Global:player.knowledge + " | Position: " + $Global:player.positionTitle + "`n"
    
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
           $destX = $Global:player.xPos
           $destY = $Global:player.yPos - 1
           $walkableFlg = CheckDestTileWalkableByPlayer $destX $destY
        
           if ($walkableFlg -eq 1)
           {
               $Global:player.xPos = $destX
               $Global:player.yPos = $destY
           }
           elseif ($walkableFlg -eq 2) # This means we will attack the enemy
           {
                PlayerAttackEnemy $destX $destY           
           }
           else
           {
               #$command = "Path blocked"
               #$Global:actionLog += $command   
           }
        }
    
        # case 'down' key:
        40 { 
           $destX = $Global:player.xPos
           $destY = $Global:player.yPos + 1
           $walkableFlg = CheckDestTileWalkableByPlayer $destX $destY
        
           if ($walkableFlg -eq 1)
           {
               $Global:player.xPos = $destX
               $Global:player.yPos = $destY
           }
           elseif ($walkableFlg -eq 2) # This means we will attack the enemy
           {
                PlayerAttackEnemy $destX $destY           
           }
           else
           {
               #$command = "Path blocked"
               #$Global:actionLog += $command   
           }
        }
    
        # case 'left' key:
        37 { 
           $destX = $Global:player.xPos - 1
           $destY = $Global:player.yPos
           $walkableFlg = CheckDestTileWalkableByPlayer $destX $destY
        
           if ($walkableFlg -eq 1)
           {
               $Global:player.xPos = $destX
               $Global:player.yPos = $destY
           }
           elseif ($walkableFlg -eq 2) # This means we will attack the enemy
           {
                PlayerAttackEnemy $destX $destY           
           }
           else
           {
               #$command = "Path blocked"
               #$Global:actionLog += $command   
           }
        }
    
        # case 'right' key:
        39 { 
           $destX = $Global:player.xPos + 1
           $destY = $Global:player.yPos
           $walkableFlg = CheckDestTileWalkableByPlayer $destX $destY
        
           if ($walkableFlg -eq 1)
           {
               $Global:player.xPos = $destX
               $Global:player.yPos = $destY
           }
           elseif ($walkableFlg -eq 2) # This means we will attack the enemy
           {
                PlayerAttackEnemy $destX $destY           
           }
           else
           {
               #$command = "Path blocked"
               #$Global:actionLog += $command   
           }
        } 
        
        # Generate new level "l" (for level)
        76 {
            CreateLevel
        }
        
        # Make entire floor visible "m" (for map)
        77 {
        
            for($i = 0; $i -le 8; $i++)
            {
                MakeVisibleFloorData $i
            }
        }
        
        # Increase player knowledge by 1 "k" (for knowledge)
        75 {
        
            $Global:player.knowledge += 1
            CheckPlayerLevelUp
        }
        
        # Turn on, or off, debug output
        68 {
            if($debugOutput -eq 0) { $debugOutput = 1 }
            else { $debugOutput = 0 }
        }
    }
    
    # Figure out which room the player is in
    $Global:player.currentGridPos = GetGridPos $Global:player.xPos $Global:player.yPos
    # Expose area of map the player is in
    MakeVisibleFloorData $Global:player.currentGridPos
    
    # Check to see if we're on a stairway tile
    if($Global:floorData[$Global:player.yPos][$Global:player.xPos] -eq "<")
    {
        $gameLevel += 1
        CreateLevel
    }
    
    # Check to see if we're on the Tome of Productivity tile
    if($Global:floorData[$Global:player.yPos][$Global:player.xPos] -eq "*")
    {
        $running = 0
        $foundTome = 1
    }
    
    # Process enemy actions
    # Loop through enemies in array, foreach up to $Global:numEnemies
    # If monster is in same grid sector, set awakeFlg = 1
    # - Once awake, a moster does not fall asleep
    # If awakeFlg -eq 1,
    # - Move toward player
    # - Will then implement:
    # If distance between enemy and player = 1 (is adjacent to), then attack player
    # Else, move toward player
    # - Try 
    
    for($i = 0; $i -lt $Global:numEnemies; $i++)
    {
        $enemyGridPos = GetGridPos $Global:Enemy[$i].xPos $Global:Enemy[$i].yPos
                   
        if($enemyGridPos -eq $Global:player.currentGridPos -and $Global:Enemy[$i].isAwake -eq 0 -and $Global:Enemy[$i].isActive -eq 1)
        {
            $Global:Enemy[$i].isAwake = 1
        }
        
        # If the enemy is not in the same grid as the player, go to sleep
        #if($enemyGridPos -ne $Global:player.currentGridPos -and $Global:Enemy[$i].isAwake -eq 1 -and $Global:Enemy[$i].isActive -eq 1)
        #{
        #    $Global:Enemy[$i].isAwake = 0
        #}
        
        # This means we should follow the player
        if($Global:Enemy[$i].isAwake -eq 1 -and $Global:Enemy[$i].isActive)
        {
            $walkableEast = CheckDestTileWalkableByEnemy ($Global:Enemy[$i].xPos + 1) ($Global:Enemy[$i].yPos) $i
            $walkableWest = CheckDestTileWalkableByEnemy ($Global:Enemy[$i].xPos - 1) ($Global:Enemy[$i].yPos) $i
            $walkableSouth = CheckDestTileWalkableByEnemy ($Global:Enemy[$i].xPos) ($Global:Enemy[$i].yPos + 1) $i
            $walkableNorth = CheckDestTileWalkableByEnemy ($Global:Enemy[$i].xPos) ($Global:Enemy[$i].yPos - 1) $i
            
        
            if($Global:Enemy[$i].xPos -lt $Global:player.xPos -and $walkableEast -ge 1)
            {
                $destX = $Global:Enemy[$i].xPos + 1
                $destY = $Global:Enemy[$i].yPos
            }
            elseif ($Global:Enemy[$i].xPos -gt $Global:player.xPos -and $walkableWest -ge 1)
            {
                $destX = $Global:Enemy[$i].xPos - 1
                $destY = $Global:Enemy[$i].yPos
            }
            elseif ($Global:Enemy[$i].yPos -lt $Global:player.yPos -and $walkableSouth -ge 1)
            {
                $destX = $Global:Enemy[$i].xPos
                $destY = $Global:Enemy[$i].yPos + 1
            }
            elseif ($Global:Enemy[$i].yPos -gt $Global:player.yPos -and $walkableNorth -ge 1)
            {
                $destX = $Global:Enemy[$i].xPos
                $destY = $Global:Enemy[$i].yPos - 1
            }
            
            $walkableFlg = CheckDestTileWalkableByEnemy $destX $destY $i
            
            
            if ($walkableFlg -eq 1)
            {
                $Global:Enemy[$i].xPos = $destX
                $Global:Enemy[$i].yPos = $destY
            }
            elseif ($walkableFlg -eq 2) # This means we will attack the enemy
            {
            
                EnemyAttackPlayer $i
            }
        }
        
#    
#    $Global:Enemy[$i].isAwake = 0
#        $Global:Enemy[$i].isActive = 1
#        $targetRelRoomXPos = Get-Random -Minimum 1 -Maximum ($Global:Room[$targetGridNum].xSize)
#        $targetRelRoomYPos = Get-Random -Minimum 1 -Maximum ($Global:Room[$targetGridNum].ySize)
#        $Global:Enemy[$i].xPos = $Global:Room[$targetGridNum].xGridPos + $Global:Room[$targetGridNum].xOffset + $targetRelRoomXPos
#        $Global:Enemy[$i].yPos = $Global:Room[$targetGridNum].yGridPos + $Global:Room[$targetGridNum].yOffset + $targetRelRoomYPos
#        $Global:Enemy[$i].enemyTypeID = 1
#        $Global:Enemy[$i].name = "spam"
#        $Global:Enemy[$i].ascii = "s"
    }
    
    # Monster variables:
    # isAwake
    # isActive
    # xPos
    # yPos
    # enemyTypeID
    # name
    
}
while ($running -eq 1)

# Check to see if player beat the game
if($foundTome -eq 1)
{
    Clear-Host
    Write-Host "Congratulations! You have found the Tome of Productivity!`n`nYou can now go be productive!`n"
    
    #Display stats
    Write-Host "Final stats"
    Write-Host "-----------`n"
    Write-Host "Player name:" $Global:player.name
    Write-Host "Player concentration:" $Global:player.concentration
    Write-Host "Player SkillSet:" $Global:player.skillSet
    Write-Host "Player Knowledge:" $Global:player.knowledge
    Write-Host "Player Position:" $Global:player.positionTitle
    Write-Host ""
}