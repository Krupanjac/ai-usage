on run arguments
    set mountPath to item 1 of arguments
    with timeout of 15 seconds
        tell application "Finder"
            set imageFolder to item (POSIX file mountPath as text)
            open imageFolder
            tell container window of imageFolder
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set bounds to {180, 180, 800, 640}
            end tell
            set viewOptions to icon view options of container window of imageFolder
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 14
            set position of item "AIUsage.app" of imageFolder to {160, 160}
            set position of item "Applications" of imageFolder to {450, 160}
            set position of item "Install.txt" of imageFolder to {305, 290}
            update imageFolder without registering applications
            delay 1
            close container window of imageFolder
        end tell
    end timeout
end run
