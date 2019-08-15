###################################################################
# SCRIPT TO GENERATE PHOTO / VIDEO GALLERY
#
# Requirements
# - hugo (generating website)
# - imagemagick (resizing thumbnails)
# - CopyTrans HEIC for Windows (HEIC conversion)
#
###################################################################

# Step 1: create temp directory

$rootDirectory = "..\"
$tempDirectory = $env:TEMP + "\diary_websites\"
$sourceDirectory = ".\src\"
$sharedSourceDirectory = $sourceDirectory + "shared\"
$repositoriesDirectory = ".\repositories\"

$generateExampleDiaries = $true
$thumbSize = 400
$thumbQuality = 90

$totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$themes = @{
    #"yinyang" = "hugo-theme-yinyang";
    "docdock" = "hugo-theme-docdock";
}

$ignoredSiteNames = ".git", "_gsdata_", "output", "generator", "diarygenerator", "temp"

$supportedStaticContentTypesAsImages = "png", "jpg", "jpeg"
$supportedStaticContentTypesAsVideos = "wma", "mov", "mp4", "avi"

$allSupportedContentTypes = New-Object System.Collections.Generic.List[string]

foreach ($supportedStaticContentTypesAsImage in $supportedStaticContentTypesAsImages)
{
    $allSupportedContentTypes.Add($supportedStaticContentTypesAsImage)
}

foreach ($supportedStaticContentTypesAsVideo in $supportedStaticContentTypesAsVideos)
{
    $allSupportedContentTypes.Add($supportedStaticContentTypesAsVideo)
}

$alwaysConvertRaw = $false
$rawFileTypes = "nef"

$alwaysConvertHeic = $false
$heicFileTypes = "heic"

#----------------------------------------------------------------------------------------------------

if ($generateExampleDiaries)
{
	Write-Host Example diary generation is enabled, copying data to diaries location
	
	foreach ($exampleDiary in Get-ChildItem ".\data\*" -Directory)
    {
		Copy-Item -Path $exampleDiary -Destination $rootDirectory -Recurse -Force
	}
}

#----------------------------------------------------------------------------------------------------

$sourceSites = New-Object System.Collections.Generic.List[string]

foreach ($childItem in Get-ChildItem $rootDirectory -Directory -Name)
{
	$include = $true
	
	foreach ($ignoredSiteName in $ignoredSiteNames)
	{
		if ($ignoredSiteName -ieq $childItem)
		{
			$include = $false
			break
		}
	}

	if (!$include)
	{
		Write-Host Ignoring $childItem
		continue
	}
	
	Write-Host Adding $childItem to diaries to generate

    $sourceSites.Add($childItem)
}

#----------------------------------------------------------------------------------------------------

foreach ($siteName in $sourceSites)
{
    Write-Host Generating site $siteName

    $siteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $siteSourceDirectory = $rootDirectory + $siteName
    $siteTempDirectory = $tempDirectory + $siteName
    $siteTempThemesDirectory = $siteTempDirectory + "\themes"
    $siteTempContentDirectory = $siteTempDirectory + "\content"
    $siteTempStaticDirectory = $siteTempDirectory + "\static"
	
	$currentDirectory = Get-Location
    $siteOutputDirectory = $currentDirectory.Path + "\..\output\" + $siteName

#----------------------------------------------------------------------------------------------------

    Write-Host Determined output directory $siteOutputDirectory

    if (Test-Path $siteTempDirectory)
    {
        Get-ChildItem -Path $siteTempDirectory -Recurse | Remove-Item -force -recurse
        Remove-Item $siteTempDirectory
    }

#----------------------------------------------------------------------------------------------------

    Write-Host Copying theme source files to temp directory $siteTempDirectory

    foreach ($themeKey in $themes.Keys)
    {
        $source = $repositoriesDirectory + $themes[$themeKey] + "\"
        $target = $siteTempThemesDirectory + "\" + $themeKey

        Write-Host Copying theme $themeKey from $source => $target

        Copy-Item $source -Filter * -Destination $target -Recurse
    }

    # Disabled for now since we have a custom build
    # Write-Host Copying easy gallery files to temp directory $siteTempDirectory

    # $source = $repositoriesDirectory + "hugo-easy-gallery\*"
    # Copy-Item $source -Filter * -Destination $siteTempDirectory -Recurse

#----------------------------------------------------------------------------------------------------

    Write-Host Copying shared source files to temp directory $siteTempDirectory

    $source = $sharedSourceDirectory + "*"
    Copy-Item $source -Filter * -Destination $siteTempDirectory -Recurse

#----------------------------------------------------------------------------------------------------

    Write-Host Replacing site name

    $siteConfigFileName = $siteTempDirectory + "\config.toml"

    $fileContents = Get-Content -Path $siteConfigFileName
    $fileContents = $fileContents.Replace('[SITENAME]', $siteName)
    $fileContents = $fileContents.Replace('[OUTPUTDIRECTORY]', $siteOutputDirectory.Replace("\", "/"))
    Set-Content -Path $siteConfigFileName -Value $fileContents

#----------------------------------------------------------------------------------------------------

    Write-Host Converting RAW files to jpeg

    $rawConversionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($rawFileType in $rawFileTypes)
    {
        $source = $siteSourceDirectory + "\"
        $extension = ".$rawFileType"

        Write-Host Checking for raw file extension $extension 

        foreach ($photoFile in Get-ChildItem -Path $source -File -Recurse | Where-Object {$_.Extension -ieq $extension})
        {
            $photoRawFileName = $photoFile.FullName
            $expectedConvertedJpegFileName = $photoRawFileName + ".jpg"
            $photoJpegFileName = $photoRawFileName.Substring(0, $photoRawFileName.Length - $extension.Length)
            $photoJpegFileName = $photoJpegFileName + ".jpg"

            Write-Host Converting RAW file $photoRawFileName to jpeg $photoJpegFileName

            if ([System.IO.File]::Exists($photoJpegFileName))
            {
                if ($alwaysConvertRaw)
                {
                    Write-Host Forcing regeneration of already converted RAW file

                    [System.IO.File]::Delete($photoJpegFileName)
                }
                else 
                {
                    Write-Host Skipping conversion since jpeg version already exists    
                }
            }

            if (![System.IO.File]::Exists($photoJpegFileName))
            {
                &.\ConvertTo-Jpeg.ps1 "$photoRawFileName"

                # Since the result is $photoNecFileName.jpg, we need to strip the .NEC (or any other extension)
                Move-Item $expectedConvertedJpegFileName $photoJpegFileName

                Write-Host Auto orienting the image
                # convert your-image.jpg -auto-orient output.jpg

                Start-Process -FilePath magick.exe -ArgumentList """$photoJpegFileName"" -auto-orient ""$photoJpegFileName""" -NoNewWindow -PassThru -Wait
            }
        }
    }

    $rawConversionStopwatch.Stop()

    Write-Host RAW to jpeg conversion for $siteName took $rawConversionStopwatch.Elapsed
    #----------------------------------------------------------------------------------------------------

    Write-Host Converting heic iOS files to jpeg

    $heicConversionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $heicConversionExecutable = "$env:SystemRoot\System32\rundll32.exe"
    $heicConversionParametersTemplate = """$env:ProgramFiles\CopyTrans HEIC for Windows\CopyTransHEICforWindows.dll"", HeicToJPEG "

    foreach ($heicFileType in $heicFileTypes)
    {
        $source = $siteSourceDirectory + "\"
        $filter = "*.$heicFileType"

        foreach ($photoFile in Get-ChildItem -Path $source -Filter $filter -Recurse | Sort-Object -Descending)
        {
            $photoHeicFileName = $photoFile.FullName
            $heicConversionParameters = $heicConversionParametersTemplate + """$photoHeicFileName"""
            $photoJpegFileName = $photoHeicFileName.Substring(0, $photoHeicFileName.Length - ($filter.Length - 1))
            $photoJpegFileName = $photoJpegFileName + ".jpg"

            Write-Host Converting heic file $photoHeicFileName to jpeg $photoJpegFileName

            if ([System.IO.File]::Exists($photoJpegFileName))
            {
                if ($alwaysConvertHeic)
                {
                    Write-Host Forcing regeneration of already converted heic file

                    [System.IO.File]::Delete($photoJpegFileName)
                }
                else 
                {
                    Write-Host Skipping conversion since jpeg version already exists    
                }
            }

            if (![System.IO.File]::Exists($photoJpegFileName))
            {
                Start-Process -FilePath $heicConversionExecutable -ArgumentList $heicConversionParameters -NoNewWindow -PassThru -Wait

                Write-Host Auto orienting the image
                # convert your-image.jpg -auto-orient output.jpg

                Start-Process -FilePath magick.exe -ArgumentList """$photoJpegFileName"" -auto-orient ""$photoJpegFileName""" -NoNewWindow -PassThru -Wait
            }
        }
    }

    $heicConversionStopwatch.Stop()

    Write-Host Heic to jpeg conversion for $siteName took $heicConversionStopwatch.Elapsed

#----------------------------------------------------------------------------------------------------

    foreach ($contentDirectory in Get-ChildItem "$siteSourceDirectory\*" -Directory)
    {
        Write-Host Copying site specific content files from $contentDirectory to temp directory

        $source = $contentDirectory.FullName + "\"
        # Get-ChildItem -Path $source -Include *.md -Recurse | Copy-Item -Destination $siteTempContentDirectory -WhatIf
        Copy-Item -Path $source -Filter *.md -Destination $siteTempContentDirectory -Recurse

        Write-Host Copying site specific static files to temp directory

        foreach ($supportedStaticContentTypeAsImage in $supportedStaticContentTypesAsImages)
        {
            $source = $contentDirectory.FullName + "\"
            $filter = "*.$supportedStaticContentTypeAsImage"
    
            Write-Host "Copying static content (photos) from $source ($filter) => $siteTempStaticDirectory"
    
            Copy-Item -Path $source -Filter $filter -Destination $siteTempStaticDirectory -Recurse -Force
        }

        foreach ($supportedStaticContentTypeAsVideo in $supportedStaticContentTypesAsVideos)
        {
            $source = $contentDirectory.FullName + "\"
            $filter = "*.$supportedStaticContentTypeAsVideo"
    
            Write-Host "Copying static content (videos) from $source ($filter) => $siteTempStaticDirectory"
    
            Copy-Item -Path $source -Filter $filter -Destination $siteTempStaticDirectory -Recurse -Force
        }
    }

#----------------------------------------------------------------------------------------------------

    Write-Host Making sure all extensions are lowercase in the target directory

    foreach ($contentDirectory in Get-ChildItem "$siteSourceDirectory\*" -Directory)
    {
        foreach ($supportedContentType in $allSupportedContentTypes)
        {
            $source = $contentDirectory.FullName + "\"
            $filter = "*.$supportedContentType"
            $expectedExtension = ".$supportedContentType"

            foreach ($contentFile in Get-ChildItem -Path $source -Filter $filter -Recurse | Sort-Object -Descending)
            {
                $fullFileName = $contentFile.FullName
                $currentExtension = $fullFileName.Substring($fullFileName.Length - ($filter.Length - 1))

                if (!$expectedExtension.Equals($currentExtension))
                {
                    Write-Host Converting extension of $fullFileName to lower-case
                    
                    $finalFullFileName = $fullFileName.Substring(0, $fullFileName.Length - ($filter.Length - 1)) + $expectedExtension
                    $tempFinalFullFileName = $finalFullFileName + ".tmp"

                    # double move since windows does not allow rename of extensions, investigate
                    # whether Rename-Item does support it
                    Move-Item $fullFileName $tempFinalFullFileName
                    Move-Item $tempFinalFullFileName $finalFullFileName
                }
            }
        }
    }

#----------------------------------------------------------------------------------------------------

    Write-Host Replacing titles in markdown files

    foreach ($markdownFile in Get-ChildItem -Path $siteTempContentDirectory -Filter *.md -Recurse | Sort-Object -Descending)
    {
        $fileContents = Get-Content -Path $markdownFile.FullName

        $fileContents = $fileContents.Replace('[TITLE]', $markdownFile.Directory.Name)

        Set-Content -Path $markdownFile.FullName -Value $fileContents
    }

#----------------------------------------------------------------------------------------------------

    Write-Host Generating thumbnails for photo galleries

    $thumbnailStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($supportedStaticContentTypeAsImage in $supportedStaticContentTypesAsImages)
    {
        $source = $siteTempStaticDirectory + "\"
        $filter = "*.$supportedStaticContentTypeAsImage"

        foreach ($photoFile in Get-ChildItem -Path $source -Filter $filter -Recurse | Sort-Object -Descending)
        {
            $photoFileName = $photoFile.FullName
            $photoThumbFileName = $photoFileName.Substring(0, $photoFileName.Length - ($filter.Length - 1)) + "-thumb.$supportedStaticContentTypeAsImage"
            $sizeParameterPart = "$thumbSize" + "x" + $thumbSize

            Write-Host Generating thumbnail $photoThumbFileName

            # $magickParameters = "convert ""$photoFileName"" -resize $sizeParameterPart^ -quality $thumbQuality -gravity center -extent $sizeParameterPart ""$photoThumbFileName"""
            $magickParameters = "convert ""$photoFileName"" -resize $sizeParameterPart^ -gravity center -extent $sizeParameterPart ""$photoThumbFileName"""

            Start-Process -FilePath magick.exe -ArgumentList $magickParameters -NoNewWindow -PassThru -Wait
        }
    }

    $thumbnailStopwatch.Stop()

    Write-Host Thumbnail generation for $siteName took $thumbnailStopwatch.Elapsed

#----------------------------------------------------------------------------------------------------

    Write-Host Replacing spaces in folder names

    $baseFolders = $siteTempStaticDirectory, $siteTempContentDirectory
    foreach ($baseFolder in $baseFolders)
    {
        $restart = $true
        while ($restart)
        {
            $restart = $false

            foreach ($directory in Get-ChildItem -Path $baseFolder -Directory -Recurse)
            {
                if ($directory.Name.Contains(" "))
                {
                    $newDirectoryName = $directory.Name.Replace(" ", "-")

                    while ($newDirectoryName.Contains("--"))
                    {
                        $newDirectoryName = $newDirectoryName.Replace("--", "-")
                    }

                    Write-Host Renaming $directory.FullName => $newDirectoryName

                    Rename-Item $directory.FullName $newDirectoryName

                    $restart = $true
                    break
                }
            }
        }
    }

#----------------------------------------------------------------------------------------------------

    Write-Host Generating site

    Start-Process -FilePath hugo.exe -WorkingDirectory $siteTempDirectory -NoNewWindow -PassThru -Wait

    $siteStopwatch.Stop()

    Write-Host Site generation for $siteName took $siteStopwatch.Elapsed
}

$totalStopwatch.Stop()

Write-Host Total generation took $totalStopwatch.Elapsed