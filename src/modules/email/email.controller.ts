import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiKeyGuard } from '../../common/guards/api-key.guard';
import { SendEmailDto, SendEmailResponseDto } from './dto/send-email.dto';
import { EmailService } from './services/email.service';

@Controller('emails')
@UseGuards(ApiKeyGuard)
export class EmailController {
  constructor(private readonly emailService: EmailService) {}

  @Post('send')
  @HttpCode(HttpStatus.OK)
  send(@Body() dto: SendEmailDto): Promise<SendEmailResponseDto> {
    return this.emailService.send(dto);
  }
}
