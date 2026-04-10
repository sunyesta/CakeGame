import json
from pathlib import Path


def export_all_files_to_json(target_directory, output_file):
    """
    Recursively scans a directory and all subdirectories for files,
    saving their relative paths to a JSON list.
    """
    path = Path(target_directory)

    if not path.is_dir():
        print(f"Error: The directory '{target_directory}' does not exist.")
        return

    # rglob('*') finds every file and folder at every depth
    # We filter for files and store the relative path for clarity
    file_list = [str(f.relative_to(path)) for f in path.rglob("*") if f.is_file()]

    try:
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(sorted(file_list), f, indent=4)
        print(
            f"Success! {len(file_list)} files found recursively and saved to {output_file}"
        )
    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == "__main__":
    # --- CONFIGURATION ---
    directory_to_scan = r"C:\Users\Mary\Downloads\Spore Sounds\WAV extracted-20260410T020449Z-3-001"  # Scans the current folder and all subfolders
    output_json_name = r"./Extra/out.txt"
    # ---------------------

    export_all_files_to_json(directory_to_scan, output_json_name)
