# Contributing to Trueshift

Thank you for your interest in contributing to Trueshift! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later (or Swift 5.9+)
- Git

### Setting Up Development Environment

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/trueshift.git
   cd trueshift
   ```

2. Build the project:
   ```bash
   swift build
   ```

3. Run tests:
   ```bash
   swift test
   ```

## Development Workflow

### Branching Strategy

- `main` - Stable release branch
- `feature/*` - New features
- `fix/*` - Bug fixes
- `docs/*` - Documentation updates

### Making Changes

1. Create a new branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes, following the code style guidelines below

3. Write or update tests as needed

4. Run the test suite:
   ```bash
   swift test
   ```

5. Build in release mode to catch any warnings:
   ```bash
   swift build -c release
   ```

### Code Style

We follow standard Swift conventions. Key points:

- Use 4-space indentation
- Keep lines under 120 characters
- Use meaningful variable and function names
- Add comments for complex logic
- Follow the existing code patterns in the project

### Running SwiftLint (Optional)

If you have SwiftLint installed:
```bash
swiftlint
```

## Testing

### Writing Tests

- Place unit tests in `Tests/TrueshiftCoreTests/`
- Follow the naming convention: `test[MethodName][Scenario]()`
- Test both success cases and edge cases

### Test Categories

- **Unit Tests**: Test individual functions and methods
- **Integration Tests**: Test component interactions (e.g., Schedule + Config)

### Running Tests

```bash
# Run all tests
swift test

# Run tests with verbose output
swift test -v

# Run specific test
swift test --filter ScheduleTests
```

## Pull Request Process

1. Update documentation if you're adding new features
2. Add tests for new functionality
3. Ensure all tests pass
4. Update CHANGELOG.md with your changes
5. Create a pull request with a clear description

### PR Title Format

- `feat: Add new feature`
- `fix: Fix bug in schedule calculation`
- `docs: Update README`
- `test: Add tests for ColorTemperature`
- `refactor: Improve code structure`

### PR Description Template

Your PR description should include:
- What changes were made
- Why the changes were necessary
- How to test the changes
- Any breaking changes

## Architecture Overview

```
trueshift/
├── Sources/
│   ├── TrueshiftCore/          # Shared library
│   │   ├── Schedule.swift     # Day phase calculations
│   │   ├── ColorTemperature.swift  # Kelvin to RGB
│   │   ├── Config.swift       # YAML config handling
│   │   └── DisplayController.swift  # macOS gamma control
│   ├── Trueshift/              # CLI tool
│   │   └── Commands/      # CLI commands
│   └── TrueshiftBar/           # Menu bar app
├── Tests/
│   └── TrueshiftCoreTests/     # Unit tests
└── docs/                  # Documentation
```

### Key Concepts

- **Phases**: The day is divided into phases (morning, preSunset, evening, night, powerDown, sleep)
- **Color Temperature**: Measured in Kelvin (1000K = warm red, 6500K = daylight)
- **Finish Line**: User-defined time after which aggressive filtering begins

## Questions or Issues?

- Check existing [issues](https://github.com/AaqifZ/trueshift/issues)
- Open a new issue for bugs or feature requests
- For questions, open a discussion

## License

By contributing to Trueshift, you agree that your contributions will be licensed under the MIT License.
