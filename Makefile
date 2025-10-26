install:
	cp ./sample1.lua ./anno-1800/trade-automation/execute.lua
	cp -r lua/* ./anno-1800/

clean/logs:
	@rm ./anno-1800/modlog.txt || true

run-sample: clean/logs install
	sleep 2
	cat ./anno-1800/modlog.txt
