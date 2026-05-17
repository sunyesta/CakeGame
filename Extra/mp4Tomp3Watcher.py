import os
import time
import threading
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from moviepy import VideoFileClip

WATCH_DIRECTORY = r"C:\Users\Mary\Videos"


class VideoHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory:
            return

        file_path = Path(event.src_path)
        if file_path.suffix.lower() == ".mp4":
            print(f"✨ New MP4 detected: {file_path.name}")

            # --- NEW: Spawn a thread so we don't block Watchdog from seeing other events ---
            threading.Thread(
                target=self.process_video, args=(file_path,), daemon=True
            ).start()

    def process_video(self, file_path):
        if self.wait_for_file_readiness(file_path):
            self.convert_mp4_to_mp3(file_path)
        else:
            print(f"⚠️ Skipping {file_path.name}: File stayed locked or busy too long.")

    def wait_for_file_readiness(self, file_path, timeout=3600):
        """Waits until the file size is strictly stable and the file is accessible."""
        # Increased timeout to 3600 seconds (1 hour) to account for long recordings/downloads
        last_size = -1
        consecutive_stable_checks = 0
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                current_size = os.path.getsize(file_path)

                # --- NEW: Require the file size to remain the SAME for multiple loops ---
                if current_size > 0 and current_size == last_size:
                    consecutive_stable_checks += 1
                else:
                    consecutive_stable_checks = 0  # Reset counter if the file grew

                last_size = current_size

                # If size hasn't changed for 4 consecutive checks (8 seconds), it's likely done
                if consecutive_stable_checks >= 4:
                    # Final strict lock check: Try opening for both reading AND writing.
                    # This will fail on Windows if another program is actively writing to it.
                    with open(file_path, "r+b"):
                        pass
                    return True

            except (OSError, IOError, PermissionError):
                # File is still strictly locked by the OS/recording software
                consecutive_stable_checks = 0

            time.sleep(2)  # Wait 2 seconds before checking again

        return False

    def convert_mp4_to_mp3(self, mp4_path):
        try:
            mp3_path = mp4_path.with_suffix(".mp3")
            print(f"🎬 Converting {mp4_path.name} to MP3...")

            # --- NEW: Use a context manager (with block) to ensure file handles are released ---
            with VideoFileClip(str(mp4_path)) as video:
                video.audio.write_audiofile(str(mp3_path), logger=None)

            print(f"✅ Success! Created: {mp3_path.name}")
        except Exception as e:
            print(f"❌ Conversion Error: {e}")


if __name__ == "__main__":
    if not os.path.exists(WATCH_DIRECTORY):
        os.makedirs(WATCH_DIRECTORY)

    event_handler = VideoHandler()
    observer = Observer()
    observer.schedule(event_handler, WATCH_DIRECTORY, recursive=False)

    print(f"🚀 Monitoring: {os.path.abspath(WATCH_DIRECTORY)}")
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()

    observer.join()
