# Copy tt files from ffpga to tt directory for tapeout
git rev-parse HEAD | head -c7 > src_commit.txt
cp src_commit.txt /foss/designs/tt_eric_launch/.
cp Makefile  /foss/designs/tt_eric_launch/test/.
cp README.md  /foss/designs/tt_eric_launch/test/.
cp requirements.txt  /foss/designs/tt_eric_launch/test/.
cp tb.gtkw	/foss/designs/tt_eric_launch/test/.
cp tb.v  /foss/designs/tt_eric_launch/test/.
cp test.py  /foss/designs/tt_eric_launch/test/.
cp ../src/forge_launcher.sv /foss/designs/tt_eric_launch/src/.
cp ../src/project.v /foss/designs/tt_eric_launch/src/.
cp ../src/lcc_syssim.sv   /foss/designs/tt_eric_launch/src/.
