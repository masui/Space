# brew install platypus

.PHONY: space

PROJECT=masui-space

space:
	/bin/rm -r -f Space.app
	platypus --name Space --interpreter /usr/bin/ruby --quit-after-execution --droppable --interface-type None --app-icon space.icns space.rb
	-/bin/rm -r -f /Applications/$(PROJECT).app
	mv Space.app /Applications/$(PROJECT).app

#	platypus -y --name Test --interpreter /usr/bin/ruby --interface-type 'Text Window' --bundled-file lib.rb test.rb

authclean:
	-/bin/rm -f ./gyazo_token
	-/bin/rm -f ./google_refresh_token
	-/bin/rm -f /Applications/$(PROJECT).app/Contents/Resources/gyazo_token
	-/bin/rm -f /Applications/$(PROJECT).app/Contents/Resources/google_refresh_token
