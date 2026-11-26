# unoq-ros2

Run ROS 2 Jazzy in Docker on the Arduino UNO Q with one command. GUI apps work on a monitor or in your browser.

📖 **Docs:** https://salmanfarisvp.github.io/unoq-ros2/

![Turtlesim in the browser](docs/assets/turtlesim/05-spawn.gif)

## Install

On the UNO Q, run:

```bash
curl -fsSL https://raw.githubusercontent.com/salmanfarisvp/unoq-ros2/main/install.sh | bash
```

## Test

Run each pair of commands in its own terminal on the board:

```bash
cd ~/ros2 && docker compose exec ros2 bash
ros2 run demo_nodes_cpp talker      # terminal 1
ros2 run demo_nodes_cpp listener    # terminal 2
```

No monitor? Open `http://<board-ip>:6080` and run `export DISPLAY=:99` in the container before starting GUI apps.

---

Based on the official Arduino guide: [ROS 2 setup](https://docs.arduino.cc/tutorials/uno-q/ros2-setup/). Not affiliated with Arduino.

UNO Q images in `docs/assets/arduino/` are © Arduino, from the [Arduino Docs](https://docs.arduino.cc/), licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
