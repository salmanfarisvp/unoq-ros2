# Quick setup

## 1. Open a terminal on the board

See [the two modes](index.md#two-ways-to-use-the-uno-q).

=== "Desktop mode"

    Connect the USB-C hub, monitor, keyboard and mouse. Log in and open a terminal.

=== "PC Hosted mode"

    From your computer, over the network:

    ```bash
    ssh arduino@<boardname>.local
    ```

    Or over the USB-C cable:

    ```bash
    adb shell
    ```

## 2. Install

```bash
curl -fsSL https://raw.githubusercontent.com/salmanfarisvp/unoq-ros2/main/install.sh | bash
```

Enter your password when asked. This takes a few minutes.

!!! note "Using SSH?"
    When it finishes, reconnect: run `exit`, then `ssh` in again.

## 3. Test

Open two terminals on the board.

=== "Terminal 1"

    ```bash
    cd ~/ros2
    docker compose exec ros2 bash
    ros2 run demo_nodes_cpp talker
    ```

=== "Terminal 2"

    ```bash
    cd ~/ros2
    docker compose exec ros2 bash
    ros2 run demo_nodes_cpp listener
    ```

You should see `I heard: [Hello World: 1]`. Press ++ctrl+c++ to stop.

## 4. GUI apps: monitor or browser

GUI apps such as turtlesim can show up in two places:

=== "Monitor on the board"

    Nothing to do. Windows open on the monitor.

    ```bash
    ros2 run turtlesim turtlesim_node
    ```

=== "Browser (no monitor)"

    On your computer, open **http://&lt;board-ip&gt;:6080**. Then, in the container shell:

    ```bash
    export DISPLAY=:99
    ros2 run turtlesim turtlesim_node
    ```

    ![Turtlesim in the browser](assets/turtlesim/01-circle.gif){ width="360" }

    Find the board's IP with `hostname -I`.

## Useful commands

Run these in `~/ros2`:

```bash
docker compose up -d            # start
docker compose down             # stop
docker compose exec ros2 bash   # open a shell
```

Next: [Pub/Sub Demo](pubsub.md)
