<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Caseta extends Model
{
    use HasFactory;

    protected $table = 'casetas';

    protected $fillable = [
        'nombre',
        'ubicacion',
    ];

    public function pasos()
    {
        return $this->hasMany(Paso::class);
    }
}

