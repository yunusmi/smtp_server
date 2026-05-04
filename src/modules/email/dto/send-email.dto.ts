import { Transform } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsEmail,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class SendEmailDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @IsEmail({}, { each: true })
  emails: string[];

  @IsOptional()
  @IsString()
  @MaxLength(998)
  subject?: string;

  @IsString()
  @IsNotEmpty()
  body: string;

  @Transform(({ value }) => {
    if (value === undefined || value === null) return false;
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value.toLowerCase() === 'true';
    return Boolean(value);
  })
  @IsBoolean()
  is_html: boolean;
}

export interface SendEmailResultItem {
  email: string;
  status: 'sent' | 'failed';
  message_id?: string;
  error?: string;
}

export interface SendEmailResponseDto {
  total: number;
  sent: number;
  failed: number;
  results: SendEmailResultItem[];
}
