# Contributing to Bitrix CDN Server

Thank you for your interest in contributing to the Bitrix CDN Server project!

## How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Development Setup

1. Clone the repository
2. Copy `.env.example` to `.env` and configure
3. Run `docker-compose -f docker-compose.dev.yml up`
4. Make your changes
5. Test thoroughly

## Testing

- Run `docker-compose -f docker-compose.yml build` to build images
- Run `make test` for native installation tests
- Ensure all health checks pass

## Code Style

- Follow existing code patterns
- Add comments for complex logic
- Update documentation when needed

## Reporting Issues

- Use GitHub Issues
- Provide detailed description
- Include logs if applicable
- Specify your environment