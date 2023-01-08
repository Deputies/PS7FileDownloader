# Requires -Version 7
function GetMaxThreads()
{
    # Use speedtest-cli to determine the maximum amount of data that can be downloaded without affecting the internet connection
    $output = & speedtest-cli --bytes
    # Parse the output to get the maximum amount of data that can be downloaded
    # in a given time period
    $regex = [Regex]::new("Download: (\d+) Mbit/s")
    $match = $regex.Match($output)
    if ($match.Success)
    {
        $maxSpeed = [double]$match.Groups[1].Value
        $maxData = [int]($maxSpeed * 125000) # 1 Mbit/s = 125000 bytes/s
    }
    # Determine the maximum number of threads to use based on the processor count
    # and the maximum amount of data that can be downloaded
    $processorCount = [Environment]::ProcessorCount
    $maxThreads = $processorCount * 2
    $chunkSize = $maxData / $maxThreads
    while ($chunkSize -lt 1000000) # 1 MB
    {
        $maxThreads /= 2
        $chunkSize = $maxData / $maxThreads
    }
    return $maxThreads
}

function Main()
{
   
# Check if the file containing the list of URLs exists
$fileName = "urls.txt"
if (!(Test-Path $fileName))
{
    # If the file doesn't exist, create it and add some example URLs
    $exampleUrls = @(
        "https://example.com/image.jpg",
        "https://example.com/video.mp4",
        "https://another-example.com/file.png"
    )
    Set-Content -Path $fileName -Value $exampleUrls
}

# Read the file containing the list of URLs
$lines = Get-Content $fileName

# Determine the maximum number of threads to use
$maxThreads = GetMaxThreads

# Create an HttpClient for downloading the files
$client = New-Object System.Net.Http.HttpClient
try
{
    # Use a SemaphoreSlim to limit the number of concurrent downloads
    $semaphore = New-Object System.Threading.SemaphoreSlim $maxThreads
    foreach ($line in $lines)
    {
        # Download the file asynchronously
        Start-ThreadJob -ScriptBlock {
            try
            {
                # Wait for a slot to be available in the semaphore
                $semaphore.Wait()

                # Extract the file name and domain from the URL
                $uri = New-Object System.Uri($line)
                $file = [System.IO.Path]::GetFileName($uri.LocalPath)
                $domain = $uri.Host

                # Create a directory for the domain, if it doesn't already exist
                $directory = Join-Path -Path (Get-Location) -ChildPath $domain
                if (!(Test-Path $directory))
                {
                    New-Item -ItemType Directory -Path $directory
                }

                # Download the file and save it to the domain's directory
                $path = Join-Path -Path $directory -ChildPath $file
                $response = $client.GetAsync($line).Result
                $response.EnsureSuccessStatusCode()
                $contentStream = $response.Content.ReadAsStreamAsync().Result
                $fileStream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Create)
                $contentStream.CopyToAsync($fileStream).Wait()
                Write-Output "Successfully downloaded $file from $domain"
            }
            catch
            {
                Write-Output "Error downloading file"
            }
            finally
            {
                # Release the semaphore slot
                $semaphore.Release()
            }
        }
    }
}
finally
{
    $client.Dispose()
}
