module("luci.controller.zlan_tailscale", package.seeall)

function index()
    entry(
        {"admin", "services", "zlan_tailscale"},
        template("zlan_tailscale/status"),
        _("Tailscale"),
        60
    ).dependent = false
end
