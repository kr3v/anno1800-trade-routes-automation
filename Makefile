install:
	cp ./sample1.lua ./anno-1800/trade-automation/execute.lua
	cp -r lua/* ./anno-1800/

clean/logs:
	@rm ./anno-1800/modlog.txt || true

run-sample: interrupt/clean clean/logs mouse/middle install
	sleep 1
	cat ./anno-1800/modlog.txt

interrupt:
	touch ./anno-1800/stop-trade-route-async-watcher
	touch ./anno-1800/stop-trade-route-loop
	touch ./anno-1800/stop-trade-executor-heartbeat

interrupt/clean:
	rm -f ./anno-1800/stop-trade-route-async-watcher || true
	rm -f ./anno-1800/stop-trade-route-loop || true
	rm -f ./anno-1800/stop-trade-executor-heartbeat || true

mouse/middle:
	xdotool mousemove 1920 1080
	mkdir anno-1800/cache || true

area-visualizations:
	@for f in $(wildcard ./anno-1800/area*.tsv); do \
		python3 ./utils/area-visualizer.py "$$f" "$$f.png"; \
	done

texts-to-yaml:
	python3 ./utils/texts-to-guid.py ./lua/texts.json /data/games/steam/steamapps/common/Anno\ 1800/maindata/data*.rda.unpack/data/config/gui/texts_english.xml
