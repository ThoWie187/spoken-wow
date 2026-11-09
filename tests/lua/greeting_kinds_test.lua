-- Greeting Not Read For: a kind of NPC the player ticks (flight master, innkeeper, vendor...) keeps
-- its greeting to itself, told by the icon the client puts on one of its window's options, the same
-- in every language. Its quests, a page the player picked an option to reach and Listen still read,
-- and the game's own greeting is heard instead. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local print = stub.print
local QUESTS = here .. "/../../addons/Spoken_Quests/"
local SPOKEN = here .. "/../../addons/Spoken/"

local world = stub.world
local Expect, Failures = require("queue_helpers").Expecter(print)

local GREETING = "Need a ride, friend?"
local LORE = "The gryphons were raised in the Aerie Peak."
-- The client's own icons on gossip options: file IDs, and the type the pre-namespace API gives.
local FLY = { name = "Show me where I can fly.", icon = 132057, type = "taxi" }
local ASK = { name = "Tell me about the gryphons.", icon = 132053, type = "gossip" }
local WARES = { name = "Let me browse your goods.", icon = 132060, type = "vendor" }
local HOME = { name = "Make this inn your home.", icon = 132052, type = "binder" }
local KINDS = {
    FlightMaster = { 132057, "taxi" }, Innkeeper = { 132052, "binder" }, Banker = { 132050, "banker" },
    Trainer = { 132058, "trainer" }, Vendor = { 132060, "vendor" }, BattleMaster = { 132051, "battlemaster" },
    GuildMaster = { 132055, "petition" }, SpiritHealer = { 132054, "healer" },
}

local function Boot(client, saved)
    stub.SetClient(client); stub.ResetSound(); stub.ResetTimers(); stub.ResetFrames()
    world.questID = 0
    stub.HidePanels()
    _G.SpokenQuestsSettings = saved
    local VO = stub.LoadQuests(QUESTS, SPOKEN)
    dofile(QUESTS .. "UI/DialogPlayButton.lua")
    VO.Addon:OnInitialize()
    local gossip = { [GREETING] = "greeting-hash", [LORE] = "lore-hash" }
    VO.DataModules:Register("TestPack", {
        SoundLengthLookupByFileName = { ["greeting-hash"] = 1, ["lore-hash"] = 1, ["101-accept"] = 1 },
        GossipLookupByNPCID = { [12345] = gossip },
        GossipLookupByNPCName = { Thorgrum = gossip },
        GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
    })
    world.npcName = "Thorgrum"
    world.npcGUID = "Creature-0-0-0-0-12345-0"
    stub.Advance(2)   -- the deferred pack load
    VO.Addon.db.profile.Audio.GossipFrequency = VO.Enums.GossipFrequency.Always
    -- Silence NPC Voices, Spoken's setting: what mutes an NPC's own greeting for a line read over it.
    _G.SpokenEnv.Addon.db.profile.Audio.AutoToggleDialog = true
    _G.SpokenEnv.Addon.db.profile.Audio.SoundChannel = "Master"

    local played = {}
    _G.Spoken:RegisterCallback("CLIP_STARTED", function(clip) table.insert(played, clip.fileName) end)
    return VO, played
end

local function Played(played)
    local text = table.concat(played, ", ")
    for i = #played, 1, -1 do played[i] = nil end
    return text ~= "" and text or "(nothing)"
end

--- The NPC's window opening with `options`; the game's dialogue setting as it stands the moment it
--- opened, which is when Spoken mutes the NPC's own greeting for a line it is going to read.
local function Talk(options)
    stub.ShowGossip(GREETING, options)
    stub.FireEvent("GOSSIP_SHOW")
    local dialog = GetCVar("Sound_EnableDialog")
    stub.Advance(1)
    return dialog
end

local function Leave()
    stub.HidePanels()
    stub.FireEvent("GOSSIP_CLOSED")
    stub.Advance(10)
    _G.Spoken:StopAll()
end

---------------------------------------------------------------- the game's own greeting
-- On the first boot only: an addon booted earlier in this process still hears the events, and
-- mutes for the line it would read.
do
    local VO, played = Boot("16001")
    local silent = VO.Addon.db.profile.Audio.SilentGreetingKinds
    Expect("an NPC Spoken reads for is muted as its window opens", Talk({ FLY, ASK }), "0")
    Leave()
    silent.FlightMaster = true
    Expect("a ticked flight master leaves the game's own greeting on", Talk({ FLY, ASK }), "1")
    Leave()
    Expect("an NPC of a kind not ticked is muted for its line, as before", Talk({ WARES, ASK }), "0")
    Leave()
    Played(played)
end

for _, client in ipairs({ "11509", "16001" }) do
    local VO, played = Boot(client)
    local silent = VO.Addon.db.profile.Audio.SilentGreetingKinds

    ---------------------------------------------------------------- off, as shipped
    for kind in pairs(KINDS) do
        Expect(client .. ": " .. kind .. " is off by default", silent[kind], false)
    end
    Talk({ FLY, ASK })
    Expect(client .. ": with nothing ticked a flight master greets as before", Played(played), "greeting-hash")
    Leave()

    ---------------------------------------------------------------- one kind ticked
    silent.FlightMaster = true
    Talk({ FLY, ASK })
    Expect(client .. ": a ticked flight master's greeting is not read", Played(played), "(nothing)")
    stub.SelectGossipOption(ASK.name)
    stub.ShowGossip(LORE, { FLY })
    stub.FireEvent("GOSSIP_SHOW")
    stub.Advance(1)
    Expect(client .. ": ...but a page the player picked an option to reach is read", Played(played), "lore-hash")
    Leave()

    Talk({ FLY })
    local button = VO.DialogPlayButton.button
    Expect(client .. ": a silent flight master's window offers Listen", button:IsShown(), true)
    button:Click()
    stub.Advance(0.2)
    Expect(client .. ": ...and Listen reads the greeting", Played(played), "greeting-hash")
    Leave()

    Talk({ FLY })
    Played(played)
    stub.HidePanels()
    world.questID = 101
    stub.ShowPanel("QuestFrameDetailPanel")
    stub.FireEvent("QUEST_DETAIL")
    stub.Advance(0.5)
    Expect(client .. ": a quest a silent flight master gives is still read", Played(played), "101-accept")
    stub.HidePanels()
    stub.FireEvent("QUEST_FINISHED")
    stub.Advance(10)
    world.questID = 0
    Played(played)

    Talk({ WARES, ASK })
    Expect(client .. ": an NPC of a kind not ticked greets", Played(played), "greeting-hash")
    Leave()

    ---------------------------------------------------------------- several roles
    silent.FlightMaster = false
    silent.Vendor = true
    Talk({ HOME, WARES })
    Expect(client .. ": one option of a ticked kind is enough: an innkeeper with wares is silent with Vendor",
        Played(played), "(nothing)")
    Leave()
    silent.Vendor = false
    Talk({ HOME, WARES })
    Expect(client .. ": ...and greets again with Vendor off", Played(played), "greeting-hash")
    Leave()

    ---------------------------------------------------------------- every kind, by its icon
    for kind, marks in pairs(KINDS) do
        silent[kind] = true
        Talk({ { name = "Option", icon = marks[1], type = marks[2] } })
        Expect(client .. ": " .. kind .. " is told by its icon", Played(played), "(nothing)")
        Leave()
        silent[kind] = false
    end
    silent.GuildMaster = true
    Talk({ { name = "I would like to create a guild crest.", icon = 132056, type = "tabard" } })
    Expect(client .. ": a tabard vendor counts as a guild master", Played(played), "(nothing)")
    Leave()
    silent.GuildMaster = false

    silent.FlightMaster = true
    Talk({ { name = FLY.name, icon = [[Interface\GossipFrame\TaxiGossipIcon]] } })
    Expect(client .. ": ...and by its texture, where a client gives the path", Played(played), "(nothing)")
    Leave()
    local namespaced = _G.C_GossipInfo
    _G.C_GossipInfo = nil
    Talk({ FLY })
    Expect(client .. ": ...and by its type, on a client without C_GossipInfo", Played(played), "(nothing)")
    Leave()
    _G.C_GossipInfo = namespaced
    silent.FlightMaster = false
end

---------------------------------------------------------------- kept across a reload
local VO = Boot("16001", {
    profileKeys = { ["Tester - Realm"] = "Default" },
    profiles = { Default = { Audio = { SilentGreetingKinds = { FlightMaster = true } } } },
})
local silent = VO.Addon.db.profile.Audio.SilentGreetingKinds
Expect("a ticked kind comes back after a reload", silent.FlightMaster, true)
Expect("...and the others stay off", silent.Innkeeper, false)

if Failures() > 0 then
    print(string.format("\n%d scenario(s) failed", Failures()))
    os.exit(1)
end
print("\nall scenarios passed")
