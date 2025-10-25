install/executor:
	rm ./anno-1800/executor.lua
	ln ./lua/executor.lua ./anno-1800/executor.lua

install/sample:
	cp ./sample1.lua ./anno-1800/trade-automation/execute.lua

clean/logs:
	@rm ./anno-1800/modlog.txt || true

run-sample: clean/logs install/sample
	sleep 1
	cat ./anno-1800/modlog.txt
