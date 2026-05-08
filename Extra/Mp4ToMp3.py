import os
from moviepy import VideoFileClip


def convert_mp4_to_mp3(mp4_file_path):
    # Ensure the provided file actually exists
    if not os.path.exists(mp4_file_path):
        print(f"Error: The file '{mp4_file_path}' does not exist.")
        return

    # Split the file path to separate the directory + filename from the extension
    base_path, _ = os.path.splitext(mp4_file_path)

    # Create the new MP3 file path in the same folder
    mp3_file_path = f"{base_path}.mp3"

    try:
        print(f"Loading '{mp4_file_path}'...")
        # Load the MP4 file
        video = VideoFileClip(mp4_file_path)

        # Extract the audio track
        audio = video.audio

        # Save the audio track as an MP3
        print(f"Exporting to '{mp3_file_path}'...")
        audio.write_audiofile(mp3_file_path)

        # Close the files to free up system memory
        audio.close()
        video.close()

        print("\nSuccess! Your audio file is ready.")

    except Exception as e:
        print(f"An error occurred during conversion: {e}")


# --- How to use it ---
if __name__ == "__main__":
    # Replace the path below with the path to your actual MP4 file.
    # You can use a relative path (e.g., "video.mp4") or an absolute path (e.g., "C:/Videos/my_video.mp4")
    target_file = r"C:\Users\Mary\Videos\2026-04-21 17-42-18.mp4"

    convert_mp4_to_mp3(target_file)
