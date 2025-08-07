"""
Tests for the calculator module.
"""

import pytest
import sys
import os

# Add src directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from calculator import Calculator


class TestCalculator:
    """Test class for Calculator functionality."""
    
    def setup_method(self):
        """Set up test fixtures before each test method."""
        self.calc = Calculator()
    
    @pytest.mark.smoke
    def test_add_positive_numbers(self):
        """Test addition of positive numbers."""
        assert self.calc.add(2, 3) == 5
        assert self.calc.add(10, 15) == 25
    
    def test_add_negative_numbers(self):
        """Test addition with negative numbers."""
        assert self.calc.add(-2, -3) == -5
        assert self.calc.add(-5, 3) == -2
        assert self.calc.add(5, -3) == 2
    
    def test_add_zero(self):
        """Test addition with zero."""
        assert self.calc.add(0, 5) == 5
        assert self.calc.add(5, 0) == 5
        assert self.calc.add(0, 0) == 0
    
    @pytest.mark.smoke
    def test_subtract(self):
        """Test subtraction."""
        assert self.calc.subtract(10, 5) == 5
        assert self.calc.subtract(5, 10) == -5
        assert self.calc.subtract(-5, -3) == -2
    
    @pytest.mark.smoke
    def test_multiply(self):
        """Test multiplication."""
        assert self.calc.multiply(3, 4) == 12
        assert self.calc.multiply(-3, 4) == -12
        assert self.calc.multiply(0, 5) == 0
    
    @pytest.mark.smoke
    def test_divide(self):
        """Test division."""
        assert self.calc.divide(10, 2) == 5
        assert self.calc.divide(9, 3) == 3
        assert self.calc.divide(7, 2) == 3.5
    
    @pytest.mark.smoke
    def test_divide_by_zero(self):
        """Test division by zero raises ValueError."""
        with pytest.raises(ValueError, match="Cannot divide by zero"):
            self.calc.divide(10, 0)
    
    def test_power(self):
        """Test power calculation."""
        assert self.calc.power(2, 3) == 8
        assert self.calc.power(5, 2) == 25
        assert self.calc.power(10, 0) == 1
        assert self.calc.power(2, -2) == 0.25
    
    def test_power_edge_cases(self):
        """Test power calculation edge cases."""
        assert self.calc.power(0, 5) == 0
        assert self.calc.power(1, 100) == 1
        assert self.calc.power(-2, 3) == -8
        assert self.calc.power(-2, 2) == 4


class TestCalculatorIntegration:
    """Integration tests for Calculator."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.calc = Calculator()
    
    @pytest.mark.smoke
    def test_complex_calculation(self):
        """Test a complex calculation using multiple operations."""
        # ((5 + 3) * 2) / 4 = 4
        result = self.calc.add(5, 3)
        result = self.calc.multiply(result, 2)
        result = self.calc.divide(result, 4)
        assert result == 4
    
    def test_calculator_state_independence(self):
        """Test that calculator operations don't affect each other."""
        calc1 = Calculator()
        calc2 = Calculator()
        
        assert calc1.add(1, 2) == 3
        assert calc2.add(3, 4) == 7
        assert calc1.multiply(2, 3) == 6
