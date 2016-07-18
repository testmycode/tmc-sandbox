#!/bin/sh
# assumes ./build.sh is already ran.

rm -Rf tmp
mkdir -p tmp
tar -C test/data/test-exercise -cf tmp/test-exercise.tar . || exit 1

MAX_OUTPUT_SIZE=20M
dd if=/dev/zero of=tmp/output.tar bs=$MAX_OUTPUT_SIZE count=1

docker create --name tmctest tmc-sandbox:latest
docker cp tmp/test-exercise.tar tmctest:/app
docker start tmctest
docker exec tmctest tar xvf test-exercise.tar
docker exec tmctest sh -c "rm **/._*"

docker exec tmctest sh -c "(/app/tmc-run; echo -n $? > exit_code.txt; true )"

docker exec tmctest touch test_output.txt valgrind.log validations.json
#summarize_text_file stdout.txt
#summarize_text_file stderr.txt

docker exec tmctest tar c test_output.txt exit_code.txt stdout.txt stderr.txt valgrind.log validations.json > tmp/output.tar

docker stop tmctest -t 2
docker rm tmctest
#docker run tmc:latest --storage-opt size=500M -v tmp:/app

# ubdbr=tmp/test-exercise.tar \
# ubdc=tmp/output.tar \
# mem=96M

tar -C tmp -xf tmp/output.tar
exit $(cat tmp/exit_code.txt)

