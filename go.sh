#!/bin/bash

sudo rm -rf ./out/*
sudo docker build --tag=s_temp-2 . && \
sudo docker run -v $PWD/out:/work/out --rm -it --privileged s_temp-2 /run.sh

