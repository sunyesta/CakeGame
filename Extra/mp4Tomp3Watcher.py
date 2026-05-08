import os
import time
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

            # --- NEW: Wait for the file to be fully written ---
            if self.wait_for_file_readiness(file_path):
                self.convert_mp4_to_mp3(file_path)
            else:
                print(
                    f"⚠️ Skipping {file_path.name}: File stayed locked or busy too long."
                )

    def wait_for_file_readiness(self, file_path, timeout=30):
        """Waits until the file size is stable and the file is accessible."""
        last_size = -1
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                current_size = os.path.getsize(file_path)
                # If size is > 0 and hasn't changed in the last second
                if current_size > 0 and current_size == last_size:
                    # Final check: Try to open the file for appending to see if it's locked
                    with open(file_path, "ab"):
                        pass
                    return True

                last_size = current_size
            except (OSError, IOError):
                # File is still locked by the recording software
                pass

            time.sleep(2)  # Wait 2 seconds between checks
        return False

    def convert_mp4_to_mp3(self, mp4_path):
        try:
            mp3_path = mp4_path.with_suffix(".mp3")
            print(f"🎬 Converting {mp4_path.name} to MP3...")

            video = VideoFileClip(str(mp4_path))
            video.audio.write_audiofile(str(mp3_path), logger=None)
            video.close()

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
