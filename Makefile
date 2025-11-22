include Makefile.vars

TRA_DIR ?= trade-route-automation
REGIONS ?= OW NW ER AR CT

install: install/mkdir
	cp ./sample1.lua "$(INSTALL_BASEDIR)/trade-automation/execute.lua"
	cp -r lua/* "$(INSTALL_BASEDIR)"

install/mkdir:
	mkdir -p "$(INSTALL_BASEDIR)"
	mkdir -p "$(INSTALL_BASEDIR)/$(TRA_DIR)"
	for region in $(REGIONS); do \
		mkdir -p "$(INSTALL_BASEDIR)/$(TRA_DIR)/$$region"; \
		mkdir -p "$(INSTALL_BASEDIR)/$(TRA_DIR)/$$region/trades"; \
	done

stop:
	touch ./anno-1800/stop-trade-route-async-watcher
	touch ./anno-1800/stop-trade-route-loop-ow
	touch ./anno-1800/stop-trade-route-loop-nw
	touch ./anno-1800/stop-trade-executor-heartbeat

interrupt: stop

clean/interrupt:
	rm -f ./anno-1800/stop-trade-route-async-watcher || true
	rm -f ./anno-1800/stop-trade-route-loop-ow || true
	rm -f ./anno-1800/stop-trade-route-loop-nw || true
	rm -f ./anno-1800/stop-trade-executor-heartbeat || true

clean/logs:
	@rm ./anno-1800/modlog.txt || true
	@rm ./anno-1800/trade-route-automation/trade-executor-history.json

clean/logs/trade:
	-@rm ./anno-1800/trade-route-automation/$(REGION)/*.json
	-@rm ./anno-1800/trade-route-automation/$(REGION)/*.log
	-@rm ./anno-1800/trade-route-automation/$(REGION)/*.hub
	-@rm ./anno-1800/trade-route-automation/$(REGION)/trades/*.log

clean:
	-make clean/interrupt
	-make clean/logs
	-for region in $(REGIONS); do \
		make clean/logs/trade REGION="$$region"; \
	done

###

run-clean: clean mouse/middle install
	sleep 1
	cat ./anno-1800/modlog.txt

run: mouse/middle install
	sleep 1
	cat ./anno-1800/modlog.txt

###

mouse/middle:
	xdotool mousemove 1920 1080
	mkdir anno-1800/cache || true

area-visualizations:
	@for f in $(wildcard ./anno-1800/area*.tsv); do \
		python3 ./utils/area-visualizer.py "$$f" "$$f.png"; \
	done

texts-to-yaml:
	python3 ./utils/texts-to-guid.py ./lua/texts.json /data/games/steam/steamapps/common/Anno\ 1800/maindata/data*.rda.unpack/data/config/gui/texts_english.xml
