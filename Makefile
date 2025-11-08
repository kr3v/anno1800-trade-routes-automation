install:
	cp ./sample1.lua ./anno-1800/trade-automation/execute.lua
	cp -r lua/* ./anno-1800/

clean/logs:
	@rm ./anno-1800/modlog.txt || true

run-sample: clean/logs mouse/middle install
	sleep 1
	cat ./anno-1800/modlog.txt

mouse/middle:
	xdotool mousemove 1920 1080
	mkdir anno-1800/cache || true

area-visualizations:
	@for f in $(wildcard ./anno-1800/area*.tsv); do \
		python3 ./utils/area-visualizer.py "$$f" "$$f.png"; \
	done

texts-to-yaml:
	python3 ./utils/texts-to-guid.py ./lua/texts.json /data/games/steam/steamapps/common/Anno\ 1800/maindata/data*.rda.unpack/data/config/gui/texts_english.xml
