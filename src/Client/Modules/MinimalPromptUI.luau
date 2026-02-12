--!strict
-- DEPRECATED: This project now uses Roblox's default `ProximityPrompt` UI.
-- This module is retained as a no-op for backward compatibility.

local MinimalPromptUI = {}

function MinimalPromptUI.Attach(_prompt: ProximityPrompt)
	return
end

function MinimalPromptUI.Detach(_prompt: ProximityPrompt)
	return
end

function MinimalPromptUI.Refresh(_prompt: ProximityPrompt)
	return
end

return MinimalPromptUI
