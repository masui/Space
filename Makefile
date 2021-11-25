# brew install platypus

.PHONY: space

PROJECT=masui-space

# ローカルなgemもアプリに含まれるように
space:
	/bin/rm -r -f Space.app
	platypus --name Space \
		--interpreter /usr/bin/ruby \
		--quit-after-execution \
		--droppable \
		--interface-type None \
		--app-icon space.icns \
		--bundled-file ruby \
		space.rb
	-/bin/rm -r -f /Applications/$(PROJECT).app
	cp -r Space.app /Applications/$(PROJECT).app

authclean:
	-/bin/rm -f ./gyazo_token
	-/bin/rm -f ./google_refresh_token
	-/bin/rm -f /Applications/$(PROJECT).app/Contents/Resources/gyazo_token
	-/bin/rm -f /Applications/$(PROJECT).app/Contents/Resources/google_refresh_token

#
# rubyフォルダの下にローカルgemが入るハズ
#
bundle:
	/usr/local/bin/bundle install --path .

dmg:
	- /bin/rm -f Space.dmg
	/usr/bin/hdiutil create -srcfolder Space.app -volname Space Space.dmg

clean:
	-/bin/rm -r -f Space.app
	-/bin/rm -r -f Space.dmg
	-/bin/rm *~
