# brew install platypus

.PHONY: space

space:
	/bin/rm -r -f Space.app
	platypus --name Space --interpreter /usr/bin/ruby --quit-after-execution --droppable --interface-type None --app-icon space.icns space.rb
	-/bin/rm -r -f /Applications/masui-space.app
	mv Space.app /Applications/masui-space.app

#	platypus -y --name Test --interpreter /usr/bin/ruby --interface-type 'Text Window' --bundled-file lib.rb test.rb
