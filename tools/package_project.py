"""Bundle project sources and the converted city, excluding original rip/caches."""
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
listed = subprocess.check_output(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
).decode().split("\0")
files = {name for name in listed if name and (root / name).is_file()}
city = "assets/maps/liberty_city.glb"
if (root / city).is_file():
    files.add(city)
(root / "build").mkdir(exist_ok=True)
output = root / "build/webs-liberty-godot.zip"
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name in sorted(files):
        archive.write(root / name, arcname="webs-liberty/" + name)
print(f"PROJECT_PACKAGED {output.name} ({output.stat().st_size // 1048576} MiB)")
