
SlopLevelerDB = {
	["runs"] = {
		{
			["char"] = "Tester-Realm",
			["class"] = "WARRIOR",
			["race"] = "Human",
			["preset"] = "modern",
			["started"] = 1000000,
			["startLevel"] = 1,
			["stopped"] = 1003600,
			["endLevel"] = 3,
			["name"] = "fixture \"run\"",
			["ev"] = {
				{
					["e"] = "zone",
					["t"] = 1000000,
					["note"] = "Northshire",
					["map"] = 425,
					["x"] = 0.4826,
					["y"] = 0.4241,
					["lvl"] = 1,
				}, -- [1]
				{
					["e"] = "accept",
					["t"] = 1000030,
					["q"] = 783,
					["title"] = "A Threat Within",
					["map"] = 425,
					["x"] = 0.4826,
					["y"] = 0.4241,
				}, -- [2]
				{
					["e"] = "turnin",
					["t"] = 1000090,
					["q"] = 783,
					["gain"] = 40,
					["money"] = 0,
					["map"] = 425,
					["x"] = 0.4891,
					["y"] = 0.4179,
				}, -- [3]
				{
					["e"] = "accept",
					["t"] = 1000100,
					["q"] = 7,
					["title"] = "Kobold Camp Cleanup",
					["map"] = 425,
					["x"] = 0.4891,
					["y"] = 0.4179,
				}, -- [4]
				{
					["e"] = "xp",
					["t"] = 1000400,
					["gain"] = 180,
					["n"] = 6,
				}, -- [5]
				{
					["e"] = "level",
					["t"] = 1000450,
					["lvl"] = 2,
				}, -- [6]
				{
					["e"] = "done",
					["t"] = 1000900,
					["q"] = 7,
					["map"] = 425,
					["x"] = 0.5302,
					["y"] = 0.3611,
				}, -- [7]
				{
					["e"] = "death",
					["t"] = 1001000,
				}, -- [8]
				{
					["e"] = "turnin",
					["t"] = 1002000,
					["q"] = 7,
					["gain"] = 450,
					["map"] = 425,
					["x"] = 0.4891,
					["y"] = 0.4179,
				}, -- [9]
				{
					["e"] = "level",
					["t"] = 1002010,
					["lvl"] = 3,
				}, -- [10]
				{
					["e"] = "mark",
					["t"] = 1002020,
					["note"] = "grind kobolds -- not wolves",
				}, -- [11]
			},
			["time"] = {
				["Northshire"] = {
					["combat"] = 1500.5,
					["drink"] = 600,
					["move"] = 1200,
					["idle"] = 299.5,
				},
			},
			["path"] = {
				"1000005|425|4826|4241", -- [1]
				"1000010|425|4900|4100", -- [2]
			},
		}, -- [1]
	},
	["recording"] = nil,
	["version"] = 1,
	["assist"] = "route",
}
