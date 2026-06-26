module("luci.controller.zlan_devices", package.seeall)

function index()
    entry(
        {"admin", "services", "zlan_devices"},
        template("zlan_devices/status"),
        _("Dispositivos locais"),
        61
    ).dependent = false
end
