local CN = _G.EVRNetNet
if not CN then
    return
end

local Mesh = _G.EVRNetMesh
if Mesh and Mesh.PeerStore then
    Mesh:PeerStore(function()
        EVRFeaturesDB = EVRFeaturesDB or {}
        EVRFeaturesDB.meshPeers = EVRFeaturesDB.meshPeers or {}
        return EVRFeaturesDB.meshPeers
    end)
end

CN:Register("evr",
    -- caps: advertise our version (tiny + non-sensitive; it rides a public post).
    function()
        return (EVRFeatures and EVRFeatures.Mesh and EVRFeatures.Mesh:BuildCaps()) or ""
    end,
    -- onPeer: hand cross-addon presence to the EVRFeatures facade for the UI.
    function(short, peer)
        if EVRFeatures and EVRFeatures.Mesh then
            EVRFeatures.Mesh:OnPeer(short, peer)
        end
    end)
