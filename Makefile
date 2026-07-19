.PHONY: test example love clean

test:
	lua tests/run.lua

example:
	lua example.lua

love: love_example/lib love_example/save_manager.lua
	cd love_example && zip -r save_example.love . -x "*.git/*" "*.love" > /dev/null
	@echo "Bundle: love_example/save_example.love"

love_example/lib: lib
	cp -r lib love_example/

love_example/save_manager.lua: save_manager.lua
	cp save_manager.lua love_example/

clean:
	rm -rf love_example/lib love_example/save_manager.lua love_example/*.love
	rm -rf save_demo/
