# Pub/Sub Demo

A **publisher** sends messages on a topic, and a **subscriber** receives them. This demo uses only shell commands.

Complete the [Quick setup](quick-setup.md) first. Then open **two** container shells:

```bash
cd ~/ros2
docker compose exec ros2 bash
```

## 1. Publish and subscribe

=== "Shell 1: publisher"

    ```bash
    ros2 topic pub --rate 1 /unoq_topic std_msgs/msg/String "{data: 'Hello from UNO Q'}"
    ```

=== "Shell 2: subscriber"

    ```bash
    ros2 topic echo /unoq_topic std_msgs/msg/String
    ```

    Expected:

    ```text
    data: Hello from UNO Q
    ---
    data: Hello from UNO Q
    ---
    ```

Press ++ctrl+c++ to stop.

## 2. As shell scripts

Create two scripts in the shared workspace. They stay on the board, even if the container is recreated.

```bash
cat > /ros2_ws/pub.sh <<'EOF'
#!/bin/bash
# Usage: ./pub.sh "your message"
ros2 topic pub --rate 1 /unoq_topic std_msgs/msg/String "{data: '${1:-Hello from UNO Q}'}"
EOF

cat > /ros2_ws/sub.sh <<'EOF'
#!/bin/bash
ros2 topic echo /unoq_topic std_msgs/msg/String
EOF

chmod +x /ros2_ws/pub.sh /ros2_ws/sub.sh
```

=== "Shell 1"

    ```bash
    /ros2_ws/pub.sh "Hi workshop"
    ```

=== "Shell 2"

    ```bash
    /ros2_ws/sub.sh
    ```

## 3. Inspect

In a third shell:

```bash
ros2 topic list                 # /unoq_topic is listed
ros2 topic info /unoq_topic     # message type, publisher and subscriber count
ros2 node list                  # running nodes
```

Next: [Turtlesim modes](turtlesim.md)
