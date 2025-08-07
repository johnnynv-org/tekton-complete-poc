"""
Main entry point for the Tekton POC project.
"""

import sys
import os

# Add src directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from calculator import main as calculator_main


if __name__ == "__main__":
    print("=== Tekton POC Project ===")
    print("Running calculator demo...")
    calculator_main()
