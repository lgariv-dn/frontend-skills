#!/usr/bin/env python3
# AI Generated file
"""
Parse JUnit XML files from Playwright E2E test results and extract structured failure information.
Usage: ./parse-junit.py [path_to_junit.xml]
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import List, Dict, Optional
import re
import json
import argparse


class TestResult:
    """Represents a single test result."""
    
    def __init__(self, name: str, classname: str, time: float, status: str, 
                 error_message: Optional[str] = None, error_type: Optional[str] = None,
                 error_details: Optional[str] = None):
        self.name = name
        self.classname = classname
        self.time = time
        self.status = status
        self.error_message = error_message
        self.error_type = error_type
        self.error_details = error_details
        self.screenshots: List[Path] = []
        self.traces: List[Path] = []
        self.videos: List[Path] = []
    
    def get_file_location(self) -> Optional[str]:
        """Extract file:line from error details if available."""
        if not self.error_details:
            return None
        
        # Look for patterns like "at tests/e2e/file.spec.ts:42:15"
        match = re.search(r'at ([\w/\-\.]+\.(?:spec|test)\.ts):(\d+):(\d+)', self.error_details)
        if match:
            return f"{match.group(1)}:{match.group(2)}"
        
        return None
    
    def get_spec_file(self) -> str:
        """Get the spec file name from classname."""
        return self.classname
    
    def get_test_folder_name(self) -> str:
        """Generate the expected test-results folder name for this test.
        
        Playwright sanitizes test names for folder names by:
        - Replacing spaces and special chars with dashes
        - Lowercasing
        - Truncating long names
        """
        # Combine classname and test name, similar to how Playwright does it
        # Remove file extension from classname
        base_name = self.classname.replace('.spec.ts', '').replace('.test.ts', '')
        # Create a sanitized folder name pattern
        sanitized = re.sub(r'[^\w\-]', '-', f"{base_name}-{self.name}")
        sanitized = re.sub(r'-+', '-', sanitized).strip('-').lower()
        return sanitized


class JUnitParser:
    """Parser for JUnit XML files."""
    
    def __init__(self, xml_path: Path):
        self.xml_path = xml_path
        self.tree = ET.parse(xml_path)
        self.root = self.tree.getroot()
    
    def parse(self) -> List[TestResult]:
        """Parse all test results from the XML."""
        results = []
        
        for testsuite in self.root.findall('.//testsuite'):
            suite_name = testsuite.get('name', 'unknown')
            
            for testcase in testsuite.findall('testcase'):
                name = testcase.get('name', 'unknown')
                classname = testcase.get('classname', 'unknown')
                time = float(testcase.get('time', 0))
                
                # Check for failure
                failure = testcase.find('failure')
                if failure is not None:
                    status = 'FAILED'
                    error_message = failure.get('message', '')
                    error_type = failure.get('type', '')
                    error_details = failure.text or ''
                else:
                    # Check for error
                    error = testcase.find('error')
                    if error is not None:
                        status = 'ERROR'
                        error_message = error.get('message', '')
                        error_type = error.get('type', '')
                        error_details = error.text or ''
                    else:
                        # Check for skipped
                        skipped = testcase.find('skipped')
                        if skipped is not None:
                            status = 'SKIPPED'
                            error_message = None
                            error_type = None
                            error_details = None
                        else:
                            status = 'PASSED'
                            error_message = None
                            error_type = None
                            error_details = None
                
                result = TestResult(
                    name=name,
                    classname=classname,
                    time=time,
                    status=status,
                    error_message=error_message,
                    error_type=error_type,
                    error_details=error_details
                )
                results.append(result)
        
        return results


def find_junit_files(base_dir: Path = Path('.')) -> List[Path]:
    """Find all junit.xml files in the workflow test directory."""
    junit_files = []
    
    # Focus on workflow test locations
    search_paths = [
        base_dir / 'playwright-results' / 'workflow',
        base_dir / 'dap-workspace' / 'reports' / 'typescript-playwright' / 'workflow',
        base_dir / 'reports' / 'typescript-playwright' / 'workflow',
    ]
    
    for search_path in search_paths:
        if search_path.exists():
            # Find all junit.xml files recursively
            junit_files.extend(search_path.rglob('junit.xml'))
    
    return junit_files


def find_test_artifacts(junit_file: Path, base_dir: Path = Path('.')) -> Dict[str, List[Path]]:
    """Find test-results directories that contain screenshots, traces, and videos.
    
    Returns a dict mapping sanitized test folder names to their artifact paths.
    """
    artifacts = {}
    
    # Common locations for test-results relative to junit.xml
    search_paths = [
        junit_file.parent / 'test-results',
        junit_file.parent.parent / 'test-results',
        base_dir / 'playwright-results' / 'test-results',
        base_dir / 'playwright-results' / 'workflow' / 'test-results',
        base_dir / 'dap-workspace' / 'reports' / 'typescript-playwright' / 'workflow' / 'test-results',
    ]
    
    for search_path in search_paths:
        if search_path.exists() and search_path.is_dir():
            # Each subfolder is a test result
            for test_folder in search_path.iterdir():
                if test_folder.is_dir():
                    folder_name = test_folder.name.lower()
                    
                    # Collect artifacts
                    screenshots = list(test_folder.glob('*.png')) + list(test_folder.glob('*.jpg'))
                    traces = list(test_folder.glob('*.zip')) + list(test_folder.glob('trace.zip'))
                    videos = list(test_folder.glob('*.webm')) + list(test_folder.glob('*.mp4'))
                    
                    if screenshots or traces or videos:
                        artifacts[folder_name] = {
                            'path': test_folder,
                            'screenshots': screenshots,
                            'traces': traces,
                            'videos': videos
                        }
    
    return artifacts


def match_test_to_artifacts(result: TestResult, artifacts: Dict[str, Dict]) -> None:
    """Match a test result to its artifacts based on name similarity."""
    test_folder_pattern = result.get_test_folder_name()
    
    for folder_name, artifact_data in artifacts.items():
        # Check if the folder name contains key parts of the test name
        # Playwright uses various naming conventions, so we check for partial matches
        test_name_parts = test_folder_pattern.split('-')
        matches = sum(1 for part in test_name_parts if part and part in folder_name)
        
        # If significant parts match, associate the artifacts
        if matches >= len(test_name_parts) * 0.5 or test_folder_pattern in folder_name:
            result.screenshots.extend(artifact_data['screenshots'])
            result.traces.extend(artifact_data['traces'])
            result.videos.extend(artifact_data['videos'])
            break
    
    # If no match found by name, check if there's only one failed test folder
    if not result.screenshots and len(artifacts) == 1:
        artifact_data = list(artifacts.values())[0]
        result.screenshots.extend(artifact_data['screenshots'])
        result.traces.extend(artifact_data['traces'])
        result.videos.extend(artifact_data['videos'])


def results_to_dict(results: List[TestResult], junit_file: Path, include_artifacts: bool = True) -> Dict:
    """Convert results to a dictionary for JSON output."""
    status_counts = {'passed': 0, 'failed': 0, 'error': 0, 'skipped': 0}
    for result in results:
        status_counts[result.status.lower()] = status_counts.get(result.status.lower(), 0) + 1
    
    failures = []
    for result in results:
        if result.status in ('FAILED', 'ERROR'):
            failure_data = {
                'name': result.name,
                'file': result.classname,
                'location': result.get_file_location(),
                'error_type': result.error_type,
                'error_message': result.error_message,
                'error_details': result.error_details,
                'time': result.time
            }
            
            if include_artifacts:
                # Include absolute paths for screenshots so models can read them
                failure_data['screenshots'] = [str(p.resolve()) for p in result.screenshots]
                failure_data['traces'] = [str(p.resolve()) for p in result.traces]
                failure_data['videos'] = [str(p.resolve()) for p in result.videos]
            
            failures.append(failure_data)
    
    return {
        'file': str(junit_file),
        'summary': {
            'total': len(results),
            **status_counts
        },
        'failures': failures,
        'reproduction_commands': {
            'affected': 'cd dap-workspace && nx affected -t e2e --base=origin/main',
            'workflow': 'cd dap-workspace && nx e2e tests-workflow-typescript',
            'specific': f"cd dap-workspace/tests/workflow/typescript && npx playwright test {failures[0]['file']}" if failures else None
        }
    }


def print_results(results: List[TestResult], junit_file: Path, output_format: str = 'text', show_screenshots: bool = False):
    """Print parsed results in the specified format."""
    if output_format == 'json':
        print(json.dumps(results_to_dict(results, junit_file), indent=2))
        return
    
    # Count by status
    status_counts = {'PASSED': 0, 'FAILED': 0, 'ERROR': 0, 'SKIPPED': 0}
    for result in results:
        status_counts[result.status] = status_counts.get(result.status, 0) + 1
    
    # Print header
    print(f"\n{'='*80}")
    print(f"JUnit Results: {junit_file.name}")
    print(f"Location: {junit_file.parent}")
    print(f"{'='*80}")
    
    # Print summary
    print(f"\n📊 Summary:")
    print(f"  ✓ Passed:  {status_counts['PASSED']}")
    print(f"  ✗ Failed:  {status_counts['FAILED']}")
    print(f"  ⚠ Error:   {status_counts['ERROR']}")
    print(f"  ⊝ Skipped: {status_counts['SKIPPED']}")
    print(f"  Total:     {len(results)}")
    
    # Print failures
    failures = [r for r in results if r.status in ('FAILED', 'ERROR')]
    if failures:
        print(f"\n{'='*80}")
        print(f"❌ Failures ({len(failures)}):")
        print(f"{'='*80}")
        
        for i, result in enumerate(failures, 1):
            print(f"\n{i}. {result.name}")
            print(f"   File: {result.classname}")
            
            location = result.get_file_location()
            if location:
                print(f"   Location: {location}")
            
            if result.error_type:
                print(f"   Type: {result.error_type}")
            
            if result.error_message:
                print(f"   Error: {result.error_message}")
            
            if result.error_details:
                # Print first 5 lines of error details
                lines = result.error_details.strip().split('\n')[:5]
                print(f"   Details:")
                for line in lines:
                    print(f"     {line}")
                if len(result.error_details.strip().split('\n')) > 5:
                    print(f"     ... (truncated)")
            
            # Print screenshot paths if available
            if result.screenshots:
                print(f"\n   📸 Screenshots ({len(result.screenshots)}):")
                for screenshot in result.screenshots:
                    print(f"      {screenshot.resolve()}")
            
            if result.traces:
                print(f"\n   🔍 Traces ({len(result.traces)}):")
                for trace in result.traces:
                    print(f"      {trace.resolve()}")
            
            if result.videos:
                print(f"\n   🎬 Videos ({len(result.videos)}):")
                for video in result.videos:
                    print(f"      {video.resolve()}")
    
    # Print reproduction command
    if failures:
        print(f"\n{'='*80}")
        print(f"🔧 Local Reproduction:")
        print(f"{'='*80}")
        
        print(f"\n# Run affected E2E tests:")
        print(f"cd dap-workspace && nx affected -t e2e --base=origin/main")
        
        print(f"\n# Run workflow E2E tests:")
        print(f"cd dap-workspace && nx e2e tests-workflow-typescript")
        
        if failures:
            first_failure = failures[0]
            spec_file = first_failure.get_spec_file()
            print(f"\n# Run specific failing test:")
            print(f"cd dap-workspace/tests/workflow/typescript && npx playwright test {spec_file}")
        
        # Print hint about viewing screenshots
        all_screenshots = [s for r in failures for s in r.screenshots]
        if all_screenshots:
            print(f"\n{'='*80}")
            print(f"📸 Failure Screenshots:")
            print(f"{'='*80}")
            print(f"\n# View screenshots (use absolute paths with image viewer or Read tool):")
            for screenshot in all_screenshots[:5]:  # Limit to first 5
                print(f"  {screenshot.resolve()}")
            if len(all_screenshots) > 5:
                print(f"  ... and {len(all_screenshots) - 5} more")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Parse JUnit XML files from Playwright E2E test results.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./parse-junit.py                          # Auto-detect junit.xml files
  ./parse-junit.py path/to/junit.xml        # Parse specific file
  ./parse-junit.py --json                   # Output as JSON (includes screenshot paths)
  ./parse-junit.py --screenshots            # Show screenshot paths for failed tests
  ./parse-junit.py --open-report            # Open HTML report after parsing

Screenshot paths are absolute so AI models can read them directly with the Read tool.

Search locations:
  - playwright-results/workflow/
  - dap-workspace/reports/typescript-playwright/workflow/
  - reports/typescript-playwright/workflow/
"""
    )
    parser.add_argument('path', nargs='?', help='Path to junit.xml file (auto-detects if not provided)')
    parser.add_argument('--json', '-j', action='store_true', help='Output results as JSON (includes screenshot/trace/video paths)')
    parser.add_argument('--screenshots', '-s', action='store_true', help='Show paths to failure screenshots for AI model analysis')
    parser.add_argument('--open-report', '-o', action='store_true', help='Open HTML report in browser after parsing')
    
    args = parser.parse_args()
    output_format = 'json' if args.json else 'text'
    show_screenshots = args.screenshots
    
    # Check if path provided
    if args.path:
        junit_path = Path(args.path)
        if not junit_path.exists():
            print(f"Error: File not found: {junit_path}", file=sys.stderr)
            sys.exit(1)
        junit_files = [junit_path]
    else:
        # Auto-detect junit.xml files
        if output_format != 'json':
            print("🔍 Searching for junit.xml files...")
        junit_files = find_junit_files()
        
        if not junit_files:
            print("Error: No junit.xml files found", file=sys.stderr)
            print("\nSearched in:", file=sys.stderr)
            print("  - playwright-results/workflow/", file=sys.stderr)
            print("  - dap-workspace/reports/typescript-playwright/workflow/", file=sys.stderr)
            print("  - reports/typescript-playwright/workflow/", file=sys.stderr)
            print("\nUsage: ./parse-junit.py [path/to/junit.xml]", file=sys.stderr)
            sys.exit(1)
        
        if output_format != 'json':
            print(f"Found {len(junit_files)} junit.xml file(s)")
    
    # For JSON output with multiple files, collect all results
    all_results = []
    
    # Parse each file
    for junit_file in junit_files:
        try:
            junit_parser = JUnitParser(junit_file)
            results = junit_parser.parse()
            
            # Find and match artifacts (screenshots, traces, videos) for failed tests
            artifacts = find_test_artifacts(junit_file)
            for result in results:
                if result.status in ('FAILED', 'ERROR'):
                    match_test_to_artifacts(result, artifacts)
            
            if output_format == 'json':
                all_results.append(results_to_dict(results, junit_file))
            else:
                print_results(results, junit_file, output_format, show_screenshots)
        except ET.ParseError as e:
            print(f"Error parsing {junit_file}: {e}", file=sys.stderr)
            continue
        except Exception as e:
            print(f"Unexpected error processing {junit_file}: {e}", file=sys.stderr)
            continue
    
    # Output collected JSON results
    if output_format == 'json':
        if len(all_results) == 1:
            print(json.dumps(all_results[0], indent=2))
        else:
            print(json.dumps(all_results, indent=2))
    else:
        print(f"\n{'='*80}\n")
    
    # If --screenshots flag is set, print a summary of all screenshots
    if show_screenshots and output_format != 'json':
        all_screenshots = []
        for junit_file in junit_files:
            try:
                junit_parser = JUnitParser(junit_file)
                results = junit_parser.parse()
                artifacts = find_test_artifacts(junit_file)
                for result in results:
                    if result.status in ('FAILED', 'ERROR'):
                        match_test_to_artifacts(result, artifacts)
                        all_screenshots.extend(result.screenshots)
            except Exception:
                continue
        
        if all_screenshots:
            print(f"\n{'='*80}")
            print(f"📸 All Failure Screenshots (use with Read tool for AI analysis):")
            print(f"{'='*80}\n")
            for screenshot in all_screenshots:
                print(str(screenshot.resolve()))
            print()
    
    # Open HTML report if requested
    if args.open_report:
        import subprocess
        for junit_file in junit_files:
            report_dir = junit_file.parent / 'playwright-report'
            if report_dir.exists():
                print(f"Opening report: {report_dir}")
                subprocess.run(['npx', 'playwright', 'show-report', str(report_dir)], check=False)


if __name__ == '__main__':
    main()
