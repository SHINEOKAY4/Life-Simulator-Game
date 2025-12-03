-- Static2: Action and Orientation type enums
-- Encodes Add/Remove/Update actions and wall orientations in 1 byte
return {
	-- Actions (indices 1-3)
	"Add",
	"Remove",
	"Update", -- Reserved for future use
	-- Wall Orientations (indices 4-7)
	"Horizontal",
	"Vertical",
	"DiagonalForward",
	"DiagonalBackward",
}
