include Makefile.vars

TRA_DIR ?= trade-route-automation
REGIONS ?= OW NW ER AR CT

BASE ?= $(INSTALL_BASEDIR_E)

install: install/mkdir
	cp -r trade_route_automation/* mods/dev/data/trade_route_automation
	cp -r mods/dev/* "$(INSTALL_BASEDIR)"

install/mkdir:
	mkdir -p "$(INSTALL_BASEDIR)"

stop:
	touch "$(BASE)/stop-trade-route-async-watcher"
	touch "$(BASE)/stop-trade-route-loop-ow"
	touch "$(BASE)/stop-trade-route-loop-nw"
	touch "$(BASE)/stop-trade-executor-heartbeat"
	touch "$(BASE)/stop-trade-routes-automation-owner"

interrupt: stop

clean/interrupt:
	rm -f "$(BASE)/stop-trade-route-async-watcher" || true
	rm -f "$(BASE)/stop-trade-route-loop-ow" || true
	rm -f "$(BASE)/stop-trade-route-loop-nw" || true
	rm -f "$(BASE)/stop-trade-executor-heartbeat" || true

clean/logs:
	-@rm "$(LOGS_DIR)"/"$(LOGS_MARKER)"*.log
	-@rm "$(LOGS_DIR)"/"$(LOGS_MARKER)"*.hub
	-@rm "$(LOGS_DIR)"/"$(LOGS_MARKER)"*.tsv

clean:
	-make clean/interrupt
	-make clean/logs

###

run-clean: clean mouse/middle install
	sleep 1
	cat $(BASE)/modlog.txt

run: mouse/middle install
	sleep 1
	@echo ""
	@echo "########"
	@echo ""
	cat $(BASE)/modlog.txt

###

mouse/middle:
	xdotool mousemove 1920 1080
	mkdir anno-1800/cache || true

area-visualizations:
	@for f in $(wildcard $(BASE)/area*.tsv); do \
		python3 ./utils/area-visualizer.py "$$f" "$$f.png"; \
	done
	for f in $(ls $(BASE)/area*.tsv); do \
		python3 ./utils/area-visualizer.py "$f" "$f.png"; \
	done

texts-to-yaml:
	python3 ./utils/texts-to-guid.py ./trade_route_automation/texts.json /data/games/steam/steamapps/common/Anno\ 1800/maindata/data*.rda.unpack/data/config/gui/texts_english.xml

###

SRC=mods/dev
TARGET=dist/TradeRoutesAutomation_DEV_$(shell git describe --tags).zip

release: install
	mkdir -p ./dist
	rm -f $(TARGET) || true
	pushd $(SRC) && zip -r ../../$(TARGET) .
