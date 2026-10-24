export class ApiError extends Error {
  constructor(public status: number, message: string, public code?: string) {
    super(message);
  }
}

export const badRequest = (msg: string) => new ApiError(400, msg, 'bad_request');
export const unauthorized = (msg = 'Not authenticated') => new ApiError(401, msg, 'unauthorized');
export const forbidden = (msg = 'Permission denied') => new ApiError(403, msg, 'forbidden');
export const notFound = (what = 'Resource') => new ApiError(404, `${what} not found`, 'not_found');
export const conflict = (msg: string) => new ApiError(409, msg, 'conflict');
