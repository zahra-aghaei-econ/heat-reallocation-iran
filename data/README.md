# Data folder

The data are not in the repository. Put the files here with exactly these names:

| File | Content | Size | MD5 |
|---|---|---|---|
| `lfs.dta` | Iran Labor Force Survey, individual level, 1384-1403 | 2.89 GB | `0bc2fc227b25403b3af2fd67c258874e` |
| `weather_daily.dta` | Daily rainfall, Tmin and Tmax by county, 1330-1402 | 1.33 GB | `fa137dd6c31eb41ecd0d9111f9ffd953` |
| `shapefile1385/geo2_ir2006.*` | 1385 county boundaries (IPUMS International), only for the maps of step 61 | 4 MB | see below |

Check a file on Windows with `certutil -hashfile lfs.dta MD5`, on macOS with `md5 lfs.dta`,
on Linux with `md5sum lfs.dta`.

MD5 of the boundary files: `.shp` 51fda60337f15a0cbe80cab8eb569bd4, `.shx` 04ad223bd4dcfd0b0e0328c7ec060af9,
`.dbf` 5aa79dec1cc34abe186d6450d2ec20bc, `.prj` c742bee3d4edfc2948a2ad08de1790a5,
`.cpg` 8edf91d5ca46b6fdbb09efc091a59d4d.

Without the boundary files everything runs; only the maps are skipped (with a message).
