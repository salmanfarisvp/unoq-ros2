# Troubleshooting

**`xhost: unable to open display ""`**
: You're on SSH. Run:
  `export DISPLAY=:0 XAUTHORITY=/home/arduino/.Xauthority`, then `xhost +local:docker`

**Turtlesim window doesn't appear**
: *Monitor:* make sure someone is logged in on the monitor, then run `xhost +local:docker` (needed after every reboot).
: *Browser:* run `export DISPLAY=:99` in the shell **before** starting turtlesim, and open `http://<board-ip>:6080`.

**Browser page at port 6080 doesn't load**
: Run `cd ~/ros2 && docker compose up -d`, then check that `ros2_display` shows as running in `docker compose ps`.

**`Package 'demo_nodes_cpp' not found`**
: Run the installer again. It adds the missing packages. Then open a new container shell.

**`ros2: command not found`**
: Open the shell with `docker compose exec ros2 bash` first.

**`docker`: permission denied**
: Log out and back in, or reboot the board.

**`no configuration file provided`**
: Run `cd ~/ros2` first.

**`XDG_RUNTIME_DIR not set` or `MESA-LOADER` warnings**
: These are harmless and can be ignored.
