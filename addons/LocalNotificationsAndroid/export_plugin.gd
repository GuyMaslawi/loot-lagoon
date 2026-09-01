@tool
extends EditorPlugin

# What actually puts the .aar into an Android build.
#
# Copied in shape from addons/GodotGooglePlayBilling/export_plugin.gd, which is
# the working precedent in this project. The one difference is that this plugin
# declares NO gradle dependencies: it is written against the Android framework
# and org.godotengine only, so there is nothing to resolve at export time and
# nothing that can drift out of step with the build template.

var export_plugin: LocalNotificationsExportPlugin


func _enter_tree() -> void:
	export_plugin = LocalNotificationsExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class LocalNotificationsExportPlugin extends EditorExportPlugin:
	var _plugin_name := "LocalNotificationsAndroid"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		return PackedStringArray([
			"%s/bin/%s/%s-%s.aar" % [_plugin_name, variant, _plugin_name, variant]
		])

	func _get_name() -> String:
		return _plugin_name
