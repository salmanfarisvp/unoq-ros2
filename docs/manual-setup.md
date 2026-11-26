# Manual setup

These are the commands the installer runs, if you'd rather do it yourself. They come from the [Arduino guide](https://docs.arduino.cc/tutorials/uno-q/ros2-setup/).

## 1. Update the system

```bash
sudo apt update && sudo apt upgrade
```

## 2. Check Docker

```bash
docker --version
docker compose version
```

## 3. Move Docker's data to /home

The root partition is small, so Docker's data goes on the larger `/home` partition.

```bash
sudo systemctl stop docker docker.socket
sudo mkdir -p /home/arduino/docker-data
sudo nano /etc/docker/daemon.json
```

Add the `data-root` line. Note the comma before it:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "2"
  },
  "data-root": "/home/arduino/docker-data"
}
```

```bash
sudo systemctl start docker
```

## 4. Get the files

```bash
docker pull ros:jazzy-ros-base
git clone https://github.com/arduino/workshop_robotics_unoq.git ~/workshop_robotics_unoq
cp -r ~/workshop_robotics_unoq/ros2 ~/ros2
cd ~/ros2
```

## 5. Edit the Dockerfile

```bash
nano Dockerfile
```

Add `nano` to the first package list. Then make the demo nodes block look like this:

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ros-jazzy-demo-nodes-py \
    ros-jazzy-demo-nodes-cpp \
    ros-jazzy-turtlesim && \
    rm -rf /var/lib/apt/lists/*
```

## 6. Edit docker-compose.yml

```bash
nano docker-compose.yml
```

Add these two lines:

```yaml
    environment:
      - ROS_DOMAIN_ID=0
      - DISPLAY=${DISPLAY:-:0}          # add
    volumes:
      - ./ros2_ws:/ros2_ws
      - /tmp/.X11-unix:/tmp/.X11-unix   # add
```

## 7. Allow display access

In a desktop terminal:

```bash
xhost +local:docker
```

Over SSH, run this first:

```bash
export DISPLAY=:0 XAUTHORITY=/home/arduino/.Xauthority
```

## 8. Build and start

```bash
docker compose up -d --build
```

Then [test it](quick-setup.md#3-test).
